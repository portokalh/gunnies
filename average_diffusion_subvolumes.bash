#!/bin/bash
humorous_statement="GASP!!! I'm...I'm dying...";

## RJA, Badea Lab, 24 January 2022
# This function approximates the '-m' option of fsl's select_dwi_vols.
# First argument: the full path to the 4D DWI nifti
# Second argument: the bvals file
# Third argument: output file
# Fourth (and up to seventh) argument(s): approx bval (per FSL, within 100 s/mm2 --i.e. +/- 100 s/mm2)

# Right away, there is concern that the recorded bval for B0 images might even be greater than 100...
#  and this could easily break the production of B0 images, with nominal bval=0...increasing it to 150.
# *a few years later...*
# Increasing to 250. Have at least one situation where"b=0" approaches 200.
tolerance=250;

# Note that this code does not test to ensure that the number of bvals in the bval table match the number of volumes in the 4D nifti.
# Also note that this doesn't seem to always clean up its temp work directory after itself on a reliable basis...may need to occassional manually clean up afterwards.

## RJA, 26 January 2022
# Using the following code to standardize all numbers to integers, even scientific notation.
# From: https://stackoverflow.com/questions/13826237/convert-scientific-notation-to-decimal-in-bash
# echo "$some_number" | awk -F"E" 'BEGIN{OFMT="%0.0f"} {print $1 * (10 ^ $2)}'

## RJA, 11 January 2022
# Need to test for ability to run ANTs PrintHeader command, and set switch to later run it on a regular blade/node:
PH_test=$(PrintHeader 2>/dev/null | grep Usage | wc -l);

if [[ "x${ANTS_PATH}x" == "xx" ]];then
    ap='';
else
    ap="${ANTS_PATH}/";
fi

if [[ -d ${GUNNIES} ]];then
	GD=${GUNNIES};
else
	GD=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd );
fi

nii4D=$1;
bvals_list=$2;
output=$3;
bval_1=$4;
bval_2=$5;
bval_3=$6;
bval_4=$7;

## Determine if we are running on a cluster--for now it is incorrectly assumed that all clusters are SGE clusters
cluster=$(bash cluster_test.bash);
if [[ $cluster ]];then
    echo "Great News, Everybody! It looks like we're running on a cluster, which should speed things up tremendously!";
    if [[ ${cluster} -eq 1 ]];then
		sub_script=${GUNNIES}/submit_slurm_cluster_job.bash;
	fi
    if [[ ${cluster} -eq 2 ]];then
		sub_script=${GUNNIES}/submit_sge_cluster_job.bash
	fi
fi


if [[ ! -f ${nii4D} ]];then
    nii4D=${PWD}/${nii4D};
 fi

if [[ ! -f ${bvals_list} ]];then
    bvals_list=${PWD}/${bvals_list};
fi

job_desc="make_DWI_average"; #e.g. co_reg
job_shorthand="meanDWI";#"Reg" for co_reg
ext="nii.gz";


sbatch_file='';

if [[ "x${identifier}x" == "xx" ]];then
    base=${nii4D##*/};
    runno=$(echo $base | cut -d '.' -f1);
else
    runno=$identifier;
fi

runno=${runno/_nii4D/};

echo "Processing runno: ${runno}";

##--------------
# Error handling

errors=0;
error_2=0;
if [[ ! -f $nii4D ]];then
    echo "ABORTING: Input file does not exist: ${nii4D}" 
    echo "    Note: User input was ${1}" >&2;
    errors=1;
fi

if [[ ! -f $bvals_list ]];then    
    echo "ABORTING: bval list does not exist: ${bvals_list}" 
    echo "    Note: User input was ${2}" >&2;
    errors=1;
fi

if [[ -e $output ]];then    
    echo "ABORTING: Output file already exists: ${output}";
    echo "    Note: This code will NOT overwrite an existing file." >&2;
    error_2=1;
fi

if [[ "x${bval_1}x" == "xx" ]];then
    echo "ABORTING: No bval of interest specified" >&2;
    errors=1;
fi

re='^-?[0-9]*[.,]?[0-9]*[eE]?-?[0-9]+$';
for c_bval in bval_1 bval_2 bval_3 bval_4;do
    #c_bval=${c_bval%.*}; #Round down to nearest integer
    test_bval=${!c_bval};
    if [[ "x${test_bval}x" != "xx" ]];then
		if ! [[ ${test_bval} =~ $re ]] ; then   
			echo "ABORTING: B-value of interest, '${test_bval}',is not a number" >&2;
			errors=1;
		else
			# Beware that the following code snippet will return zero for an empty input--not good! (hence the test 2 lines above)
			# Beware that the following code snippet will return a number even with alpha input--not good! (hence the test 1 line above)
			integer_bval=$( echo "${test_bval}" | awk -F"E" 'BEGIN{OFMT="%0.0f"} {print $1 * (10 ^ $2)}'); 
			#echo "c_bval=${c_bval}"
			#echo "integer_bval=${integer_bval}";
			eval "${c_bval}=${integer_bval}";
		fi
    fi
done

average_all=0;
if [[ ${bval_1} == -1 ]];then
    average_all=1;
    #NOTE: This is NOT implemented, partly because I realized that if we want to average over an entired 4D nifti, there are easier ways to do--usually with a single command
fi

if (($errors));then
    echo "${humorous_statement}" &&  exit 1;
fi


##---------------
# Setup work folders
if [[ -d ${BIGGUS_DISKUS} ]];then
    top_dir=${BIGGUS_DISKUS};
else
    top_dir=$PWD;
fi

work="${top_dir}/${job_desc}_${runno}_b${bval_1}-tmp_work/";
if (($error_2));then
    if [[ "x${work}x" != "xx" ]];then
		if [[ -d ${work} ]];then
			echo "Cleaning up completely leftover work directory now...";
			echo "Removing: ${work}";
			rm -fr $work;
		fi
    fi
    echo "${humorous_statement}" &&  exit 0;
fi

if [[ ! -d ${work} ]];then
    mkdir -p -m 775 ${work};
fi


sbatch_folder="${work}/sbatch/";
if [[ ! -d ${sbatch_folder} ]];then
    mkdir -p -m 775 ${sbatch_folder};
fi

##---------------

vol_list='';
jid_list='';
reassemble_list=" ";
c_vol=0;

echo "Extracting the following bvals (with tolerance of +/- ${tolerance}):  bvals=${bval_1} ${bval_2} ${bval_3} ${bval_4}";
for bvalue in $(cat $bvals_list);do
    bvalue=$( echo "$bvalue" | awk -F"E" 'BEGIN{OFMT="%0.0f"} {print $1 * (10 ^ $2)}');
    echo $bvalue
   for c_bval in $bval_1 $bval_2 $bval_3 $bval_4;do
       
       if [[ "x${c_bval}x" != "xx" ]];then
	   l_bval=$((c_bval-$tolerance));
	   u_bval=$((c_bval+$tolerance));
		   if [[ ${bvalue} -lt ${u_bval} ]] && [[ ${bvalue} -gt ${l_bval} ]];then            
			   vol_list="${vol_list}${c_vol},";
			   num_string=$(printf "%03d\n" ${c_vol}); 
			   vol_xxx_out="${work}/${runno}_m${num_string}.${ext}";
			   reassemble_list="${reassemble_list} ${vol_xxx_out} ";
			   echo "Isolating volume ${c_vol}...";
			   if [[ ! -e ${vol_xxx_out} ]];then
			   # Note: I need to make sure $c_vol should be indexed from 0 (vs from 1) for this command
			   extract_cmd="${ap}ExtractSliceFromImage 4 ${nii4D} ${vol_xxx_out} 3 ${c_vol} 0;";
				   if ((${cluster}));then
					   job_name="extract_vol_${c_vol}_from_${runno}";
					   sub_cmd="${sub_script} ${sbatch_folder} ${job_name} 0 0 ${extract_cmd}";
					  # echo ${sub_cmd}; # Commented out because it was just too dang chatty!
						if [[ ${cluster} -eq 1 ]];then
							job_id=$(${sub_cmd} | cut -d ' ' -f 4);						   
						elif [[ ${cluster} -eq 2 ]]
						   job_id=$(${sub_cmd} | tail -1 | cut -d ';' -f1 | cut -d ' ' -f4);
						fi	
						
						if ((! $?));then
							jid_list="${jid_list}${job_id},";
						fi
				   else
					   ${extract_command};
				   fi
			   fi
			   c_vol=$((c_vol+1));
			   continue 2;
		   fi
       fi
   done
c_vol=$((c_vol+1));
done

#Trim trailing comma from job id & volume lists:
jid_list=${jid_list%,};
vol_list=${vol_list%,};
echo "volume list = ${vol_list}";

if [[ "x${jid_list}x" == "xx" ]];then
    jid_list=0;
fi

average_cmd="${ap}AverageImages 3 ${output} 0 ${reassemble_list};";
if [[ "x${vol_list}x" != "xx" ]];then
    
    if [[ ! -f ${output} ]];then
		if ((${cluster}));then
			job_name="final_averaging_${job_desc}_${runno}_b${bval_1}";
			# REMOVE 'echo' in rm_cmd after testing!
			rm_cmd="if [[ -f ${output} ]];then if [[ \"x${work}x\" != \"xx\" ]] && [[ -d ${work} ]];then rm -fr $work;fi;fi;" 
			final_cmd="${average_cmd}${rm_cmd}";	
			sub_cmd="${sub_script} ${sbatch_folder} ${job_name} 32000M  ${jid_list} ${final_cmd}";
			if [[ ${cluster} -eq 1 ]];then
				job_id=$(${sub_cmd} | cut -d ' ' -f 4);						   
			elif [[ ${cluster} -eq 2 ]]
			   job_id=$(${sub_cmd} | tail -1 | cut -d ';' -f1 | cut -d ' ' -f4);
			fi	
						
	
			echo "JOB ID = ${job_id}; Job Name = ${job_name}";
		else
			${average_cmd};
		fi
    fi 
else
    echo "Whoops! No bvalues found with that/those values in ${bvals_list}.";
    echo "No output image will be generated.";
    echo "Cleaning up completely useless work directory now...";
    if [[ "x${work}x" != "xx" ]];then
		if [[ -d ${work} ]];then
			rm -fr $work;
		fi
    fi
fi


if [[ -f ${output} ]];then
    if [[ "x${work}x" != "xx" ]];then
		if [[ -d ${work} ]];then
			echo "Output image appears to successfully persist in time and space."; 
			echo "Cleaning up temporary work directory now...";
			rm -fr $work;
		fi
    fi
fi 

if ((${cluster}));then
	re='^[1-9]?[0-9]+$';
	if [[ ${job_id} =~ $re ]];then
		exit_status=0;
		echo "FINAL_JOB_ID=${job_id}"
	else
		exit_status=1;
	fi
else	
	if [[ -f ${output} ]];then
		exit_status=0;
	else
		exit_status=1;
	fi
fi

exit "${exit_status}";
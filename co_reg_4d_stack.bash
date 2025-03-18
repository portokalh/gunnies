#!/bin/bash

## RJA, Badea Lab, 22 April 2020
# This function uses antsRegistration from the ANTs toolbox to affinely register all images in a 4D nifti stack to the first volume.
# In the '-work' folder are the individual images after the calculated transforms have been applied to the corresponding input image.
# These images are then reconcatonated into a registered 4D nift stack and placed in the '-results' folder. 
# Also in the '-results' folder are the individual transforms for each volume.
# Currently these transforms are NOT being applied to any DWI b-vector table.

# Though it doesn't belong here on a long-term basis, some minimal DWI processing has been included here.
# Right now, this will extract the b-table from a .bxh header, if there is one immediately next to the 4D nifti stack, and has the same name, save for the extension (.bxh instead of .nii or .nii.gz)

# There is hope that it will also spit out the dwi image contrast while it's at it...but that's a WIP.

## RJA, 30 December 2021
# All volumes can be registered to an arbitrary image now. Instead of the passing a "dti" flag as the third option, that option is now the full path to the that target. ("dti" is set to zero)

## RJA, 11 January 2022
# Need to test for ability to run ANTs PrintHeader command, and set switch to later run it on a regular blade/node:
PH_test=$(PrintHeader 2>/dev/null | grep Usage | wc -l);

nii4D=$1;
identifier=$2;
dti=$3;

if [[ ! -f ${nii4D} ]];then
    nii4D=${PWD}/${nii4D};
fi

job_desc="co_reg"; #e.g. co_reg
job_shorthand="Reg";#"Reg" for co_reg
ext="nii.gz";


sbatch_file='';

if [[ "x${identifier}x" == "xx" ]];then
    base=${nii4D##*/};
    runno=$(echo $base | cut -d '.' -f1);
else
    runno=$identifier;
fi

reg_to_vol_zero=1;
target_vol='';
if [[ -f ${dti} ]];then
    echo "Registering to: $dti.";
    target_vol=$dti;
    reg_to_vol_zero=0;
    dti=0;
fi


echo "Processing runno: ${runno}";

if [[ ! -f $nii4D ]];then    
    echo "ABORTING: Input file does not exist: ${nii4D}" && exit 1;
fi

if [[ -d ${GUNNIES} ]];then
	GD=${GUNNIES};
else
	GD=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd );
fi
## Determine if we are running on a cluster--for now it is incorrectly assumed that all clusters are SGE clusters
cluster=$(bash cluster_test.bash);
if [[ $cluster ]];then
    echo "Great News, Everybody! It looks like we're running on a cluster, which should speed things up tremendously!";
    if [[ ${cluster} == 'SLURM' ]];then
		sub_script=${GD}/submit_slurm_cluster_job.bash;
	fi
    if [[ ${cluster} == 'SGE' ]];then
		sub_script=${GD}/submit_sge_cluster_job.bash
	fi
fi



#YYY_cmd="PrintHeader $nii4D 2 | cut -d 'x' -f4";
YYY_cmd="PrintHeader $nii4D 2"; # Piping stdout seems to not work when running...agnostically(?)
# I can't believe I'm about to do something so fucking retarded as this...
if ((${PH_test}));then
    PH_result=$(${YYY_cmd});
else
    PH_result=$(ssh blade16 ${YYY_cmd} );
fi

YYY=$(echo ${PH_result} |  cut -d 'x' -f4 );

XXX=$(expr $YYY - 1);

declare -i XXX;

echo "Total number of volumes: $YYY";
if ((${reg_to_vol_zero}));then
    echo "Number of independently oriented volumes: $XXX";
else
    echo "Number of independently oriented volumes: $YYY";
fi

if [[ $XXX -lt 10 ]];then
    zeros='0';
elif [[ $XXX -lt 100 ]];then
    zeros='00';
else
    zeros='000';
fi

discard='1000';
discard=${discard/${zeros}/};
zero='0';
zero_pad=${zeros/${zero}/};

inputs="${BIGGUS_DISKUS}/${job_desc}_${runno}_m${zeros}-inputs/";
work="${BIGGUS_DISKUS}/${job_desc}_${runno}_m${zeros}-work/";
results="${BIGGUS_DISKUS}/${job_desc}_${runno}_m${zeros}-results/";

vol_zero="${inputs}${runno}_m${zeros}.${ext}";

if [[ ! -d ${inputs} ]];then
    mkdir -p -m 775 ${inputs};
fi

if [[ ! -d ${work} ]];then
    mkdir -p -m 775 ${work};
fi

sbatch_folder="${work}/sbatch/";
if [[ ! -d ${sbatch_folder} ]];then
    mkdir -p -m 775 ${sbatch_folder};
fi

if [[ ! -d ${results} ]];then
    mkdir -p -m 775 $results;
fi

prefix="${BIGGUS_DISKUS}/${job_desc}_${runno}_m${zeros}-inputs/${runno}_m.nii.gz";

## To-do (2 June 2020 Tues): Make this a cluster job; use for later jobs: echo "#\$ -hold_jid ${jid_list}" >> ${sbatch_file};

if [[ ! -e ${vol_zero} ]];then
    if [[ ! -e ${prefix/_m/_m1000} ]];then
	echo "Splitting up nii4D volume...";
	${ANTSPATH}/ImageMath 4 ${prefix} TimeSeriesDisassemble ${nii4D};
    fi

    for file in $(ls ${inputs});do
	new_file=${inputs}/${file/_m${discard}/_m};
	if [[ ! -e ${new_file} ]];then
	    ln -s $file ${new_file};
	fi
    done
fi

work_vol_zero="${work}/${job_shorthand}_${runno}_m${zeros}.${ext}";
jid_list='';


#for nn in $(seq 1 $XXX);do
if (( ! ${reg_to_vol_zero}));then
    start_vol=0;
    reassemble_list="";
else
    start_vol=1;
    target_vol=${vol_zero};
    if [[ ! -e ${work_vol_zero} ]];then
	ln -s ${vol_zero} ${work_vol_zero};
    fi
    reassemble_list="${work_vol_zero} ";
fi

echo "Target for coregistration: ${target_vol}";

echo "Dispatching co-registration jobs to the cluster:";

# Note the following line is necessarily complicated, as...
# the common sense line ('for nn in {01..$XXX}') does not work...
# https://stackoverflow.com/questions/169511/how-do-i-iterate-over-a-range-of-numbers-defined-by-variables-in-bash
for nn in $(eval echo "{${zero_pad}${start_vol}..$XXX}");do
    # num_string=$nn;
    # if [[ $nn -lt 10 ]];then
    # num_string="0${nn}";
    # fi
   	num_string=$nn;
	vol_xxx="${inputs}${runno}_m${num_string}.${ext}";
	out_prefix="${results}xform_${runno}_m${num_string}.${ext}";
	xform_xxx="${out_prefix}0GenericAffine.mat";
	vol_xxx_out="${work}/${job_shorthand}_${runno}_m${num_string}.${ext}";
	reassemble_list="${reassemble_list} ${vol_xxx_out} ";

	name="${job_desc}_${runno}_m${num_string}";
	sbatch_file="${sbatch_folder}/${name}.bash";
	#source_sbatch="${BIGGUS_DISKUS}/sinha_co_reg_nii4D_qsub_master.bash";
	#cp ${source_sbatch} ${sbatch_file};
	if [[ ! -e ${xform_xxx} ]] ||  [[ ! -e ${vol_xxx_out} ]];then


	    bj_temp_test=1;
	    if ((${bj_temp_test}));then
			reg_cmd="if [[ ! -e ${xform_xxx} ]];then ${ANTSPATH}/antsRegistration  --float -d 3 -v  -m Mattes[ ${target_vol},${vol_xxx},1,32,regular,0.3 ] -t Affine[0.05] -c [ 100x100x100,1.e-7,15 ] -s 2x1x0.5vox -f 4x2x1 -u 1 -z 1 -o ${out_prefix};fi";
	    else	
			reg_cmd="if [[ ! -e ${xform_xxx} ]];then ${ANTSPATH}/antsRegistration  --float -d 3 -v  -m Mattes[ ${target_vol},${vol_xxx},1,32,regular,0.3 ] -t Affine[0.05] -c [ 100x100x100,1.e-5,15 ] -s 0x0x0vox -f 4x2x1 -u 1 -z 1 -o ${out_prefix};fi";
	    fi
	    apply_cmd="if [[ ! -e ${vol_xxx_out} ]];then ${ANTSPATH}/antsApplyTransforms -d 3 -e 0 -i ${vol_xxx} -r ${vol_zero} -o ${vol_xxx_out} -n Linear -t ${xform_xxx}  -v 0 --float;fi";
	   
	    final_cmd="${reg_cmd};${apply_cmd}";	
	    sub_cmd="${sub_script} ${sbatch_folder} ${name} 0 0 ${final_cmd}";
		if [[ ${cluster} -eq 1 ]];then
			job_id=$(${sub_cmd} | cut -d ' ' -f 4);						   
		elif [[ ${cluster} -eq 2 ]];then
		   job_id=$(${sub_cmd} | tail -1 | cut -d ';' -f1 | cut -d ' ' -f4);
		fi	
						
	    if ((! $?));then
			jid_list="${jid_list}${job_id},";
	    fi	    
	   
	fi
done

#Trim trailing comma from job id list:
if ((${jid_list}));then
    jid_list=${jid_list%,};
else
    jid_list='0';
fi

reg_nii4D="${results}/${job_shorthand}_${runno}_nii4D.${ext}";
assemble_cmd="${ANTSPATH}/ImageMath 4 ${reg_nii4D} TimeSeriesAssemble 1 0 ${reassemble_list}";
#if [[ 1 -eq 2 ]];then # Uncomment when we want to short-circuit this to OFF
if [[ ! -f ${reg_nii4D} ]];then
    name="assemble_nii4D_${job_desc}_${runno}_m${zeros}";
    sub_cmd="${GUNNIES}/submit_sge_cluster_job.bash ${sbatch_folder} ${name} 0 ${jid_list} ${assemble_cmd}";
    echo ${sub_cmd};
	if [[ ${cluster} -eq 1 ]];then
		job_id=$(${sub_cmd} | cut -d ' ' -f 4);						   
	elif [[ ${cluster} -eq 2 ]];then
	   job_id=$(${sub_cmd} | tail -1 | cut -d ';' -f1 | cut -d ' ' -f4);
	fi	
						
    echo "JOB ID = ${job_id}; Job Name = ${name}";

fi 

if [[ "x${dti}x" == "x1x" ]];then
    bvecs=${reg_nii4D/\.${ext}/_fsl_bvecs.txt};
    bvecs=${bvecs/${job_shorthand}_/};
    bvals=${bvecs/bvecs/bvals};

    dsi_btable=${bvecs/fsl/dsi};
    dsi_btable=${dsi_btable/bvecs/btable};

    if [[ ! -f ${bvecs} ]];then
	bxh=${nii4D/${ext}/bxh};
	bvec_cmd="extractdiffdirs --fsl ${bxh} ${bvecs} ${bvals}";
	dsi_bvec_cmd="extractdiffdirs --dsistudio ${bxh} ${dsi_btable}";
	echo $bvec_cmd;
	$bvec_cmd;

	echo $dsi_bvec_cmd;
	$dsi_bvec_cmd;
    fi

    

fi

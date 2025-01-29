#! /bin/bash
# Process name
proc_name="diffusion_prep_MRtrix"; # Not gonna call it diffusion_calc so we don't assume it does the same thing as the civm pipeline

## 15 June 2020, BJA: I still need to figure out the best way to pull out the non-zero bval(s) from the bval file.
## For now, hardcoding it to 1000 to run Whitson data. # 8 September 2020, BJA: changing to 800 for Sinha data.
## 24 January 2022, BJA: Changing bval to 2400 for Manisha's data.
## 21 January 2025, BJA: Totally rewrote based around chatGPT's answer when asking how to preprocess using MRtrix

# Will try to auto-extract bval going forward...though it is not yet designed to handle multi-shell acquisitions.
#nominal_bval='2000';

GD=${GUNNIES}
if [[ ! -d ${GD} ]];then
	echo "env variable '$GUNNIES' not defined...failing now..."  && exit 1
fi

BD=${BIGGUS_DISKUS}
if [[ ! -d ${BD} ]];then
	echo "env variable '$BIGGUS_DISKUS' not defined...failing now..."  && exit 1
fi

# This script is designed to be ran on human data, so let's be sneaky and ensure that it
# ends up in a 'human' directory instead of a 'mouse'

BD2=${BD%/}
mama_dir=${BD2%/*};
baby_dir=${BD2##*/};
if [[ 'xmousex' == "x${baby_dir}x" ]];then
	BD="${mama_dir}/human/";
	export BIGGUS_DISKUS=$BD;
	if [[ ! -d $BD ]];then
		mkdir -m 775 ${BD};
	fi
fi


id=$1;
raw_nii=$2;
no_cleanup=$3;

if [[ "x1x" == "x${no_cleanup}x" ]];then
    cleanup=0;
else
    cleanup=1;
fi

echo "Processing diffusion data with runno/id: ${id}.";

work_dir=${BD}/${proc_name}_${id};
echo "Work directory: ${work_dir}";
if [[ ! -d ${work_dir} ]];then
    mkdir -pm 775 ${work_dir};
fi

sbatch_folder=${work_dir}/sbatch;
if [[ ! -d ${sbatch_folder} ]];then
    mkdir -pm 775 ${sbatch_folder};
fi

nii_name=${raw_nii##*/};
ext="nii.gz";

bxheader=${raw_nii/nii.gz/bxh}
#    echo "Input nifti = ${raw_nii}.";
#    echo "Input header = ${bxheader}.";

bvecs=${work_dir}/${id}_bvecs.txt;
bvals=${bvecs/bvecs/bvals};

echo "Bvecs: ${bvecs}";

if [[ ! -f ${bvecs} ]];then
	cp ${raw_nii/\.nii\.gz/\.bvec} ${bvecs}
fi

if [[ ! -f ${bvals} ]];then
	cp ${raw_nii/\.nii\.gz/\.bval} ${bvals}
fi



if [[ ! -f ${bvecs} ]];then
    bvec_cmd="extractdiffdirs --colvectors --writebvals --fieldsep=\t --space=RAI ${bxheader} ${bvecs} ${bvals}";
    $bvec_cmd;
fi
#######
###
# 3. --> 1. Convert DWI data to MRtrix format

presumed_debiased_stage='05';
# Add one to presumed_debiased_stage:
pds_plus_one='06';
debiased=${work_dir}/${id}_${presumed_debiased_stage}_dwi_nii4D_biascorrected.mif
if [[ ! -f ${debiased} ]];then
	stage='01';
	dwi_mif=${work_dir}/${id}_${stage}_dwi_nii4D.mif;
	if [[ ! -f ${dwi_mif} ]];then
		# Moved convert to mif from stage 3 to stage 1
		#mrconvert ${degibbs} ${dwi_mif} -fslgrad ${bvecs} ${bvals};
		mrconvert ${raw_nii} ${dwi_mif} -fslgrad ${bvecs} ${bvals};
	fi
	
	if [[ ! -f ${dwi_mif} ]];then
		echo "Process died during stage ${stage}" && exit 1;
	fi
	###
	# 1. --> 2. Denoise the raw DWI data
	stage='02';
	#denoised=${work_dir}/${id}_${stage}_dwi_nii4D_denoised.nii.gz
	denoised=${work_dir}/${id}_${stage}_dwi_nii4D_denoised.mif
	if [[ ! -f ${denoised} ]];then
		# Moved denoise from stage 1 to stage 2:
		#dwidenoise $raw_nii ${denoised}
		dwidenoise ${dwi_mif} ${denoised}
	fi
	
	if [[ ! -f ${denoised} ]];then
		echo "Process died during stage ${stage}" && exit 1;
	elif ((${cleanup}));then
		if [[ -f ${dwi_mif} ]];then
			rm ${dwi_mif};
		fi
	fi
	
	###
	# 2. --> 3 Gibbs ringing correction (optional)
	stage='03';
	#degibbs=${work_dir}/${id}_${stage}_dwi_nii4D_degibbs.nii.gz;
	degibbs=${work_dir}/${id}_${stage}_dwi_nii4D_degibbs.mif;
	if [[ ! -f ${degibbs} ]];then
		mrdegibbs ${denoised} ${degibbs}
	fi
	
	if [[ ! -f ${degibbs} ]];then
		echo "Process died during stage ${stage}" && exit 1;
	elif ((${cleanup}));then
		if [[ -f ${denoised} ]];then
			rm ${denoised};
		fi
	fi
	###
	# 4. Perform motion and eddy current correction (requires FSL's `eddy`)
	stage='04'
	preprocessed=${work_dir}/${id}_${stage}_dwi_nii4D_preprocessed.mif;
	if [[ ! -f ${preprocessed} ]];then
		# Moved around first 3 steps; updating accordingly:
		# dwifslpreproc ${dwi_mif} ${preprocessed} -rpe_none -pe_dir AP -eddy_options " --repol " -nocleanup
		json_string=" -pe_dir AP ";
		maybe_json=${raw_nii/\.nii\.gz/json};
		# Using the json file does not seem to properly provide the PE direction. 
		#if [[ -f ${maybe_json} ]];then
		#	json_string=" -json_import ${maybe_json} ";
		#fi
		dwifslpreproc ${degibbs} ${preprocessed} ${json_string} -rpe_none -eddy_options " --repol --slm=linear " -scratch ${work_dir}/ -nthreads 8
		# Note: '--repol' automatically corrects for artefact due to signal dropout caused by subject movement
	fi
	
	if [[ ! -f ${preprocessed} ]];then
		echo "Process died during stage ${stage}" && exit 1;
	elif ((${cleanup}));then
		if [[ -f ${degibbs} ]];then
			rm ${degibbs};	
		fi
	fi
	###
	# 5. Bias field correction (optional but recommended)
	stage='05';
	debiased=${work_dir}/${id}_${stage}_dwi_nii4D_biascorrected.mif
	if [[ ! -f ${debiased} ]];then
		dwibiascorrect ants ${preprocessed} ${debiased} -scratch ${work_dir}/
	fi
	
	if [[ ! -f ${debiased} ]];then
		echo "Process died during stage ${stage}" && exit 1;
	elif ((${cleanup}));then
		if [[ -f ${preprocessed} ]];then
			rm ${preprocessed};
		fi
	fi
else
	echo "Debiased mif file already exists; skipping to Stage ${pds_plus_one}." 
fi

###
# 6. Fit the tensor model
stage='06';
dt=${work_dir}/${id}_${stage}_dt.mif;
if [[ ! -f ${dt} ]];then
	dwi2tensor ${debiased} ${dt};
fi

if [[ ! -f ${dt} ]];then
	echo "Process died during stage ${stage}" && exit 1;
fi
###
# 7. Compute FA (and other metrics, if desired)
stage='07';
fa=${work_dir}/${id}_${stage}_fa.mif;
fa_nii=${work_dir}/${id}_fa.nii.gz;
adc=${work_dir}/${id}_${stage}_adc.mif;
adc_nii=${work_dir}/${id}_adc.nii.gz;
rd=${work_dir}/${id}_${stage}_rd.mif;
rd_nii=${work_dir}/${id}_rd.nii.gz;
ad=${work_dir}/${id}_${stage}_ad.mif;
ad_nii=${work_dir}/${id}_ad.nii.gz;
out_string=" ";

if [[ ! -f ${fa_nii} || ! -f ${adc_nii} || ! -f ${rd_nii} || ! -f ${ad_nii} ]];then

	if [[ ! -f ${fa} || ! -f ${adc} || ! -f ${rd} || ! -f ${ad} ]];then
		for contrast in fa adc rd ad;do
			c_mif=${work_dir}/${id}_${stage}_${contrast}.mif;
			nii=${work_dir}/${id}_${contrast}.nii.gz;
			if [[ ! -f ${nii} && ! -f ${c_mif} ]];then
				out_string="${out_string} -${contrast} ${c_mif}"
			fi
		done
		tensor2metric ${dt} ${out_string};
	fi

	if [[ ! -f ${fa} || ! -f ${adc} || ! -f ${rd} || ! -f ${ad} ]];then
		echo "Process died during stage ${stage}" && exit 1;
	fi
fi

###
# 8. Convert FA (or other metrics) to NIfTI for visualization
for contrast in fa adc rd ad;do
	mif=${work_dir}/${id}_${stage}_${contrast}.mif;
	nii=${work_dir}/${id}_${contrast}.nii.gz;
	
	if [[ ! -f ${nii} ]];then
		mrconvert ${mif} ${nii};
	fi
	
	if [[ -f ${nii} && -f ${mif} ]];then
		if ((${cleanup}));then
			rm ${mif};
		fi
	fi
done


###
# 9. Extract b0 and dwi from debiased nii4D

b0=${work_dir}/${id}_b0.nii.gz;
dwi=${work_dir}/${id}_dwi.nii.gz;

mif=${debiased};
final_nii4D=${debiased/\.mif/\.nii\.gz};
if [[ ! -f ${b0} || ! -f ${dwi} ]];then
	if [[ ! -f ${final_nii4D} ]];then
		mrconvert ${mif} ${final_nii4D};
	fi
elif ((${cleanup}));then
	if [[ -f  ${final_nii4D} ]];then
		rm ${final_nii4D};
	fi
fi
dv=' ';#' 2>/dev/null ';


#nbv_cmd="more ${bvals} | tr -s [:space:] '\n' | sed 's|.*|(&+50)/100*100|' $dv | bc $dv | sort $dv | uniq $dv | tail $dv | tr -s [:space:] '\n' $dv | tail -1 $dv";
#echo ${nbv_cmd}
#nominal_bval=`$nbv_cmd`;
#echo "nominal_bval=\$(more ${bvals} | tr -s [:space:] '\n' | sed 's|.*|(&+50)/100*100|' $dv | bc $dv | sort $dv | uniq $dv | tail $dv | tr -s [:space:] '\n' $dv | tail -1 $dv )";
nominal_bval=$(cat ${bvals} $dv | tr -s [:space:] '\n' | sed 's|.*|(&+50)/100*100|' | bc | sort | uniq | tail | tr -s [:space:] '\n' | tail -1 );
echo $nominal_bval

echo "bval_zero=\$(more ${bvals} | tr -s [:space:] '\n' | sed 's|.*|(&+50)/100*100|' | bc | sort | uniq | tail | tr -s [:space:] '\n' | head -1)";
bval_zero=$(more ${bvals} | tr -s [:space:] '\n' | sed 's|.*|(&+50)/100*100|' | bc | sort | uniq | tail | tr -s [:space:] '\n' | head -1);
echo $bval_zero

if [[ ! -f ${dwi} ]];then
	${GD}/average_diffusion_subvolumes.bash ${final_nii4D} $bvals ${dwi} ${nominal_bval};
fi

if [[ ! -f ${b0} ]];then
	${GD}/average_diffusion_subvolumes.bash ${final_nii4D} $bvals ${b0} ${bval_zero};
fi

if [[ -f ${b0} && -f ${dwi} ]];then
	if ((${cleanup}));then
		if [[ -f  ${final_nii4D} ]];then
			rm ${final_nii4D};
		fi
	fi
fi

echo "Pipeline: ${proc_name}_${id} has completed! Thanks for patronizing this wonderful script!" && exit 0
#######
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
fi


###
# 4. Perform motion and eddy current correction (requires FSL's `eddy`)
stage='04'
preprocessed=${work_dir}/${id}_${stage}_dwi_nii4D_preprocessed.mif;
if [[ ! -f ${preprocessed} ]];then
	# Moved around first 3 steps; updating accordingly:
	# dwifslpreproc ${dwi_mif} ${preprocessed} -rpe_none -pe_dir AP -eddy_options " --repol " -nocleanup
	dwifslpreproc ${degibbs} ${preprocessed} -rpe_none -pe_dir AP -eddy_options " --repol " -nocleanup
fi

if [[ ! -f ${preprocessed} ]];then
	echo "Process died during stage ${stage}" && exit 1;
fi
###
# 5. Bias field correction (optional but recommended)
stage='05';
debiased=${work_dir}/${id}_${stage}_dwi_nii4D_biascorrected.mif
if [[ ! -f ${debiased} ]];then
	dwibiascorrect ants ${preprocessed} ${debiased}
fi

if [[ ! -f ${debiased} ]];then
	echo "Process died during stage ${stage}" && exit 1;
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
adc=${work_dir}/${id}_${stage}_adc.mif;
rd=${work_dir}/${id}_${stage}_rd.mif;
ad=${work_dir}/${id}_${stage}_ad.mif;
if [[ ! -f ${fa} || ! -f ${adc} || ! -f ${rd} || ! -f ${ad} ]];then
	tensor2metric ${dt} -fa ${fa} -adc ${adc} -rd ${rd} -ad ${ad};
fi

if [[ ! -f ${fa} || ! -f ${adc} || ! -f ${rd} || ! -f ${ad} ]];then
	echo "Process died during stage ${stage}" && exit 1;
fi
###
# 8. Convert FA (or other metrics) to NIfTI for visualization
for contrast in fa adc rd ad;do
	mif=${work_dir}/${id}_${stage}_${contrast}.mif;
	nii=${work_dir}/${id}_${contrast}.nii.gz;
	if [[ ! -f ${nii} ]];then
		mrconvert ${mif} ${nii}
	fi
done

b0=${work_dir}/${id}_b0.nii.gz;
dwi=${work_dir}/${id}_dwi.nii.gz;

mif=${debiased};
final_nii4D=${debiased/\.mif/\.nii\.gz};
if [[ ! -f ${b0} || ! -f ${dwi} ]];then
	mrconvert ${mif} ${final_nii4D};
fi

###
# 9. Extract b0 and dwi from debiased nii4D
nominal_bval=$(more ${bvals} | tr -s [:space:] "\n" | sed 's|.*|(&+50)/100*100|' | bc | sort | uniq | tail | tr -s [:space:] "\n" | tail -1);
bval_zero=$(more ${bvals} | tr -s [:space:] "\n" | sed 's|.*|(&+50)/100*100|' | bc | sort | uniq | tail | tr -s [:space:] "\n" | head -1);

if [[ ! -f ${dwi} ]];then
	${GD}/average_diffusion_subvolumes.bash ${final_dwi_nii4D} $bvals ${dwi} ${nominal_bval};
fi

if [[ ! -f ${b0} ]];then
	${GD}/average_diffusion_subvolumes.bash ${final_dwi_nii4D} $bvals ${dwi} 0 ${bval_zero};
fi

#######
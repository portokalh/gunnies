#! /bin/bash
# Process name
proc_name="diffusion_prep"; # Not gonna call it diffusion_calc so we don't assume it does the same thing as the civm pipeline

## 15 June 2020, BJA: I still need to figure out the best way to pull out the non-zero bval(s) from the bval file.
## For now, hardcoding it to 1000 to run Whitson data. # 8 September 2020, BJA: changing to 800 for Sinha data.
## 24 January 2022, BJA: Changing bval to 2400 for Manisha's data.

# Will try to auto-extract bval going forward...though it is not yet designed to handle multi-shell acquisitions.
#nominal_bval='2000';

GD=${GUNNIES}
if [[ ! -d ${GD} ]];then
	echo "env variable '$GUNNIES' not defined...failing now..."  && exit 1
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

work_dir=${BIGGUS_DISKUS}/${proc_name}_${id};

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

if [[ ! -f ${bvecs} ]];then
    bvec_cmd="extractdiffdirs --colvectors --writebvals --fieldsep=\t --space=RAI ${bxheader} ${bvecs} ${bvals}";
    $bvec_cmd;
fi
#######
##
# 1. Denoise the raw DWI data
stage='01';
denoised=${work_dir}/${id}_${stage}_dwi_nii4D_denoised.nii.gz
if [[ ! -f ${denoised} ]];then
	dwidenoise $raw_nii ${denoised}
fi
###
# 2. Gibbs ringing correction (optional)
stage='02';
degibbs=${work}_dir/${id}_${stage}_dwi_nii4D_degibbs.nii.gz;
if [[ ! -f ${degobbs} ]];then
	mrdegibbs ${denoised} ${degibbs}
fi

###
# 3. Convert DWI data to MRtrix format
stage='03';
dwi_mif=${work_dir}/${id}_${stage}_dwi_nii4D.mif;
if [[ ! -f ${dwi_mif} ]];then
	mrconvert ${degibbs} ${dwi_mif} -fslgrad ${bvecs} ${bvals};
fi


###
# 4. Perform motion and eddy current correction (requires FSL's `eddy`)
stage='04'
preprocessed=${work_dir}/${id}_${stage}_dwi_nii4D_preprocessed.mif;
if [[ ! -f ${preprocessed} ]];then
	dwifslpreproc ${dwi_mif} ${preprocessed} -rpe_none -pe_dir AP -eddy_options " --repol " -nocleanup
fi

###
# 5. Bias field correction (optional but recommended)
stage='05';
debiased=${work_dir}/${id}_${stage}_dwi_nii4D_biascorrected.mif
if [[ ! -f ${debiased} ]];then
	dwibiascorrect ants ${preprocessed} ${debiased}
fi

###
# 6. Fit the tensor model
stage='06';
dt=${work_dir}/${id}_${stage}_dt.mif;
if [[ ! -f ${dt} ]];then
	dwi2tensor ${debiased} ${dt};
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
final_nii_nii4D=${debiased/\.mif/\.nii\.gz};
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

if [[ -! -f ${b0} ]];then
	${GD}/average_diffusion_subvolumes.bash ${final_dwi_nii4D} $bvals ${dwi} 0 ${bval_zero};
fi

#######
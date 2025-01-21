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




orient_string=${work_dir}/${runno}_relative_orientation.txt;

# Make dwi for mask generation purposes.
tmp_mask="${work_dir}/${id}_tmp_mask.${ext}";
#mask="${work_dir}/${id}_mask.${ext}";
raw_dwi="${work_dir}/${id}_raw_dwi.nii.gz";
if [[ ( ! -f ${mask} || ! -e ${orient_string} ) &&  ! -f ${tmp_mask} ]];then
   
    if [[ ! -f ${raw_dwi} ]];then
	#echo  select_dwi_vols ${raw_nii} $bvals ${raw_dwi} ${nominal_bval}  -m;
	#select_dwi_vols ${raw_nii} $bvals ${raw_dwi} ${nominal_bval}  -m;
	/mnt/clustertmp/common/rja20_dev/gunnies/average_diffusion_subvolumes.bash ${raw_nii} $bvals ${raw_dwi} ${nominal_bval};
    fi
    
    if [[ ! -f ${tmp_mask} ]];then
	if (($human));then
	    bet ${raw_dwi} ${tmp_mask/_mask/} -m -n;
	#else
	    ##########enter strip mask stuff here
	fi
    fi
fi

if [[ "x${cleanup}x" == "x1x" ]] && [[ -f ${tmp_mask} ]] && [[ -f ${raw_dwi} ]];then
    rm ${raw_dwi};
fi


# Run Local PCA Denoising algorithm on 4D nifti:
# Note: the LPCA python has a logical switch that will produce another, confounding mask (though arguably better). This is currently switched off, but can cause confusion and delay if switched on and not properly documented.
denoised_nii="${work_dir}/LPCA_${id}_nii4D.nii.gz";
masked_nii="${work_dir}/${nii_name}";
masked_nii=${masked_nii/.$ext/_masked.$ext};

if [[ ! -f ${denoised_nii} ]];then

    if [[ ! -f ${masked_nii} ]];then
	fslmaths ${raw_nii} -mas ${tmp_mask} ${masked_nii} -odt "input";
    fi

    /mnt/clustertmp/common/rja20_dev/gunnies/basic_LPCA_denoise.py ${id} ${masked_nii} ${bvecs} ${work_dir};
fi

if [[ "x${cleanup}x" == "x1x" ]] && [[ -f ${denoised_nii} ]] && [[ -f ${masked_nii} ]];then
    rm ${masked_nii};
fi

# Run coregistration/eddy current correction:

L_id="LPCA_${id}";
coreg_nii="${BIGGUS_DISKUS}/co_reg_${L_id}_m00-results/Reg_${L_id}_nii4D.${ext}";
if [[ ! -f ${coreg_nii} ]];then
    /mnt/clustertmp/common/rja20_dev/gunnies/co_reg_4d_stack.bash ${denoised_nii} ${L_id} 0;
fi

coreg_inputs="${BIGGUS_DISKUS}/co_reg_${L_id}_m00-inputs";
coreg_work=${coreg_inputs/-inputs/-work};
if [[ "x${cleanup}x" == "x1x" ]] && [[ -f ${coreg_nii} ]] && [[ -d ${coreg_inputs} ]];then
    rm -r ${coreg_inputs};
fi

if [[ "x${cleanup}x" == "x1x" ]] && [[ -f ${coreg_nii} ]] && [[ -d ${coreg_work} ]];then
    rm -r ${coreg_work};
fi

# Generate tmp DWI:
tmp_dwi_out=${work_dir}/${id}_tmp_dwi.${ext};
dwi_out=${work_dir}/${id}_dwi.${ext};
if [[ ! -f $dwi_out ]];then
    if [[ ! -f $tmp_dwi_out ]];then
	#select_dwi_vols ${coreg_nii} $bvals ${tmp_dwi_out} ${nominal_bval}  -m;
	/mnt/clustertmp/common/rja20_dev/gunnies/average_diffusion_subvolumes.bash ${coreg_nii} $bvals ${tmp_dwi_out} ${nominal_bval};
    fi
elif [[ "x${cleanup}x" == "x1x" ]] && [[ -f ${tmp_dwi_out} ]];then
    rm ${tmp_dwi_out};
fi

# Generate tmp B0:
tmp_b0_out=${work_dir}/${id}_tmp_b0.${ext};
b0_out=${work_dir}/${id}_b0.${ext};
if [[ ! -f ${b0_out} ]];then
    if [[ ! -f ${tmp_b0_out} ]];then
	#select_dwi_vols ${coreg_nii} $bvals ${tmp_b0_out} 0  -m;
	# Sometimes values of up to 200 can show up in the btable for the B0 volumes...adding "150" to try to catch these cases.
	/mnt/clustertmp/common/rja20_dev/gunnies/average_diffusion_subvolumes.bash ${coreg_nii} $bvals ${tmp_b0_out} 0 150;
    fi
elif [[ "x${cleanup}x" == "x1x" ]] && [[ -f ${tmp_b0_out} ]];then
    rm ${tmp_b0_out};
fi

# Generate DTI contrasts and perform some tracking QA:
c_string='';
if [[ "x${cleanup}x" == "x1x" ]];then
    c_string=' --cleanup ';
fi

/mnt/clustertmp/common/rja20_dev/gunnies/dti_qa_with_dsi_studio.bash ${coreg_nii} $bvecs ${tmp_mask} $work_dir $c_string;

# Create RELATIVE links to DSI_studio outputs:
for contrast in fa0 rd ad md; do
    real_file=$(ls ${work_dir}/*.fib.gz.${contrast}.${ext} | head -1 ); # It will be fun times if we ever have more than one match to this pattern...
    contrast=${contrast/0/};
    linked_file="${work_dir}/${id}_${contrast}.${ext}";

    # We need to make sure that we didn't accidentally link to a non-existent file.
    if [[ -L ${linked_file} ]] && [[ ! -f $(readlink ${linked_file}) ]];then
        unlink ${linked_file};
    fi

    # This should prevent linking to a non-existent file in the future.
    if [[ ! -L ${linked_file} ]] && [[ -f ${real_file} ]];then
	ln -s "./${real_file##*/}" ${linked_file};
    fi
done


# For Whitson data (at least) we empirically know that we need to move the data from LAS to RAS:
# Enforce header consistency, based on fa from DSI Studio before reorienting data (will break if there's an affine xform in header)

# Hopefully the new auto-detect-orientation code will work...

img_xform_exec='/mnt/clustertmp/common/rja20_dev//matlab_execs_for_SAMBA//img_transform_executable/run_img_transform_exec.sh';
mat_library=' /mnt/clustertmp/common/rja20_dev//MATLAB2015b_runtime/v90';

# Enforce header consistency, based on mask--no, scratch that--based on fa from DSI Studio
# No scratch that--fa doesn't necessarily have a consistent center of mass!
md="${work_dir}/${id}_md.${ext}";

# I'm not going to say specifically why, but, we only need to compare orientations between the mask and the md.
# This only works on clean runs, and won't catch b0s or dwis that have been previously incorrectly turned.

if [[ ! -e ${orient_string} ]];then
    file=${work_dir}/${id}_tmp_mask.${ext};
    orient_test=$(/mnt/clustertmp/common/rja20_dev/gunnies/find_relative_orientation_by_CoM.bash $md $file);
    echo ${orient_test} > $orient_string;
else
    orient_test=$(more $orient_string);
fi

for contrast in tmp_dwi tmp_b0 tmp_mask;do
    file=${work_dir}/${id}_${contrast}.${ext};
    if [[ -e $file ]];then
	/mnt/clustertmp/common/rja20_dev/gunnies/nifti_header_splicer.bash ${md} ${file} ${file};
    fi    
done



#   file=${work_dir}/${id}_tmp_mask.${ext};
#    orient_test=$(/mnt/clustertmp/common/rja20_dev/gunnies/find_relative_orientation_by_CoM.bash $md $file);

orientation_in=$(echo ${orient_test} | cut -d ',' -f2 | cut -d ':' -f2);
orientation_out=$(echo ${orient_test} | cut -d ',' -f1 | cut -d ':' -f2);
echo "flexible orientation: ${orientation_in}";
echo "reference orientation: ${orientation_out}";

for contrast in dwi b0 mask;do
    img_in=${work_dir}/${id}_tmp_${contrast}.${ext};
    img_out=${work_dir}/${id}_${contrast}.${ext};
    if [[ ! -e ${img_out} ]];then
	if [[ "${orientation_out}" != "${orientation_in}" ]];then
	    echo "TRYING TO REORIENT...${contrast}";
	    if [[ -e $img_in ]] && [[ ! -e $img_out ]];then 
		reorient_cmd="${img_xform_exec} ${mat_library} ${img_in} ${orientation_in} ${orientation_out} ${img_out}";
		${reorient_cmd};
		if [[ -e ${img_out} ]];then
		    rm $img_in;
		fi
	    elif [[ -e ${img_out} ]];then
		rm $img_in;
	    fi
	    
	else
	    mv $img_in $img_out;
	fi
    fi
done

# Turning off the following code block for now...
if (( 0 ));then
    file=${work_dir}/${id}_mask.${ext};
    orient_test=$(/mnt/clustertmp/common/rja20_dev/gunnies/find_relative_orientation_by_CoM.bash $md $file);

    orientation_in=$(echo ${orient_test} | cut -d ',' -f2 | cut -d ':' -f2);
    orientation_out=$(echo ${orient_test} | cut -d ',' -f1 | cut -d ':' -f2);
    echo "flexible orientation: ${orientation_in}";
    echo "reference orientation: ${orientation_out}";
    if [[ "${orientation_out}" != "${orientation_in}" ]];then
	echo "TRYING TO REORIENT...MASK!";
	img_in=${work_dir}/${id}_tmp2_mask.${ext};
	img_out=${work_dir}/${id}_mask.${ext};
    
	mv $img_out $img_in;
	reorient_cmd="${img_xform_exec} ${mat_library} ${img_in} ${orientation_in} ${orientation_out} ${img_out}";
	${reorient_cmd};
	if [[ -e ${img_out} ]];then
	    rm $img_in;
	fi
    fi
fi

for contrast in dwi b0 mask;do
    file=${work_dir}/${id}_${contrast}.${ext};
    /mnt/clustertmp/common/rja20_dev/gunnies/nifti_header_splicer.bash ${md} ${file} ${file};
    
done


# Apply updated mask to dwi and b0.
mask=${work_dir}/${id}_mask.${ext};

#for contrast in dwi b0;do
#    file=${work_dir}/${id}_${contrast}.${ext};
#    fslmaths ${file} -mas ${mask} ${file} -odt "input";
#done

if [[ "x${cleanup}x" == "x1x" ]] && [[ -f ${tmp_mask} ]] &&  [[ -f ${mask} ]];then
    rm ${tmp_mask};
fi


if [[ "x${cleanup}x" == "x1x" ]] && [[ -f ${tmp_dwi_out} ]] &&  [[ -f ${dwi_out} ]];then
    rm ${tmp_dwi_out};
fi

if [[ "x${cleanup}x" == "x1x" ]] && [[ -f ${tmp_b0_out} ]] &&  [[ -f ${b0_out} ]];then
    rm ${tmp_b0_out};
fi

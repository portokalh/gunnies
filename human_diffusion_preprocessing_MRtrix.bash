#! /bin/bash
# Process name
proc_name="diffusion_prep_MRtrix"; # Not gonna call it diffusion_calc so we don't assume it does the same thing as the civm pipeline

## 15 June 2020, BJA: I still need to figure out the best way to pull out the non-zero bval(s) from the bval file.
## For now, hardcoding it to 1000 to run Whitson data. # 8 September 2020, BJA: changing to 800 for Sinha data.
## 24 January 2022, BJA: Changing bval to 2400 for Manisha's data.
## 21 January 2025, BJA: Totally rewrote based around chatGPT's answer when asking how to preprocess using MRtrix

# Will try to auto-extract bval going forward...though it is not yet designed to handle multi-shell acquisitions.
#nominal_bval='2000';

#GD=${GUNNIES}
#if [[ ! -d ${GD} ]];then
#	echo "env variable '$GUNNIES' not defined...failing now..."  && exit 1
#fi

if [[ -d ${GUNNIES} ]];then
	GD=${GUNNIES};
else
	GD=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd );
fi

## Determine if we are running on a cluster--for now it is incorrectly assumed that all clusters are SGE clusters
cluster=$(bash cluster_test.bash);
if [[ $cluster ]];then
    if [[ ${cluster} -eq 1 ]];then
		sub_script=${GD}/submit_slurm_cluster_job.bash;
	fi
    if [[ ${cluster} -eq 2 ]];then
		sub_script=${GD}/submit_sge_cluster_job.bash
	fi
	echo "Great News, Everybody! It looks like we're running on a cluster, which should speed things up tremendously!";
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

# I think we should always use fsl...our home brewed coreg seems to be too loosy-goosy
use_fsl=1;
if ((${use_fsl}));then
	work_dir=${BD}/${proc_name}_${id};
else
	work_dir=${BD}/${proc_name}_with_coreg_${id};
fi
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

mrtrix_grad_table="${bvals%.b*}_grad_corrected.b";

#######
presumed_debiased_stage='05';
# Add one to presumed_debiased_stage:
pds_plus_one='06';
debiased=${work_dir}/${id}_${presumed_debiased_stage}_dwi_nii4D_biascorrected.mif
if [[ ! -f ${debiased} ]];then

	###
	# Adding stage 00, checking the gradient table.
	stage='00';	
	if [[ ! -e ${mrtrix_grad_table} ]];then	
		dwigradcheck ${raw_nii} -fslgrad ${bvecs} ${bvals} -export_grad_mrtrix ${mrtrix_grad_table};
	fi
	
	if [[ ! -f ${mrtrix_grad_table} ]];then
		echo "Process died during stage ${stage}" && exit 1;
	fi
	
	###
	# 3. --> 1. Convert DWI data to MRtrix format
	stage='01';
	dwi_mif=${work_dir}/${id}_${stage}_dwi_nii4D.mif;
	if [[ ! -f ${dwi_mif} ]];then
		# Moved convert to mif from stage 3 to stage 1
		#mrconvert ${degibbs} ${dwi_mif} -fslgrad ${bvecs} ${bvals};
		mrconvert ${raw_nii} ${dwi_mif} -grad ${mrtrix_grad_table};
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
	# OR alternatively, see how well our coreg performs.
	stage='04';

	preprocessed=${work_dir}/${id}_${stage}_dwi_nii4D_preprocessed.mif;
	temp_mask=${work_dir}/${id}_mask_tmp.mif;
	if [[ ! -f ${preprocessed} ]];then
		if ((${use_fsl}));then
		
			# Going to make a temporary mask with dwi2mask, but use fsl's bet later from the b0
			
			if [[ ! -f ${tmp_mask} ]];then
				dwi2mask ${degibbs} ${temp_mask};
			fi
			
			mask_string=' ';
			if [[ -f ${tmp_mask} ]];then
				mask_string=" -mask ${temp_mask} ";
			fi

			# Moved around first 3 steps; updating accordingly:
			# dwifslpreproc ${dwi_mif} ${preprocessed} -rpe_none -pe_dir AP -eddy_options " --repol " -nocleanup
			json_string=" -pe_dir AP ";
			maybe_json=${raw_nii/\.nii\.gz/json};
			# Using the json file does not seem to properly provide the PE direction. 
			#if [[ -f ${maybe_json} ]];then
			#	json_string=" -json_import ${maybe_json} ";
			#fi
			eddy_opts='--repol --slm=linear'; 
			n_shells=$(mrinfo -shell_bvalues ${degibbs} | wc -w);
			if [[ ${n_shells} -gt 2 ]];then 
				eddy_opts="${eddy_opts} --data_is_shelled ";
			fi
			dwifslpreproc ${degibbs} ${preprocessed} ${json_string} -rpe_none -eddy_options " ${eddy_opts} " -scratch ${work_dir}/ -nthreads 10 ${mask_string};
			#dwifslpreproc ${degibbs} ${preprocessed} ${json_string} -rpe_none -eddy_options " --repol --slm=linear " -scratch ${work_dir}/ -nthreads 8
			# Note: '--repol' automatically corrects for artefact due to signal dropout caused by subject movement
		else
			zeros='00';
			echo "mrinfo ${degibbs} | grep Dimen | cut -d 'x' -f4 | tr -d [:space:]";
			n_diffusion=$(mrinfo ${degibbs} | grep Dimen | cut -d 'x' -f4 | tr -d [:space:]);
			if [[ ${n_diffusion} -gt 100 ]];then
				zeros='000';
			fi
			coreg_nii="${BIGGUS_DISKUS}/../mouse/co_reg_${id}_m${zeros}-results/Reg_${id}_nii4D.nii.gz";
			echo " Coreg _nii = ${coreg_nii}"
			degibbs_nii=${work_dir}/${id}_${stage}_dwi_nii4D_degibbs.nii.gz;
			
			if [[ ! -f ${degibbs_nii} && ! -f ${coreg_nii} ]];then
				mrconvert ${degibbs} ${degibbs_nii};
			fi

			if [[ ! -f ${coreg_nii} ]];then
				jid=$(${GUNNIES}/co_reg_4d_stack.bash ${degibbs_nii} ${id} 0);
				echo "Last coregistration job id is ${jid}";
			fi
			if [[ $cluster && $jid ]];then
				t=30;
				test=1;
				while (($test));do
				
					if [[ $cluster -eq 1 ]];then
						test=$(squeue -h -j $jid 2>/dev/null | wc -l);
					else
						# The following test will also work for comma-separated job list, returning the list of
						# jobs currently running.

						test=$(qstat | grep -E ${jid//,/\|} 2>/dev/null | wc -l);
					fi
					echo '.';
					sleep 15;
					let "t--";
				done	
			fi
					
			if [[ -f ${coreg_nii} ]];then
				mrconvert ${coreg_nii} ${preprocessed}  -grad ${mrtrix_grad_table};
			fi
		fi	
	fi
	
	if [[ ! -f ${preprocessed} ]];then
		echo "Process died during stage ${stage}" && exit 1;
	elif ((${cleanup}));then
		if [[ -f ${degibbs} ]];then
			rm ${degibbs};	
		fi
		
		if [[ -f ${degibbs_nii} ]];then
			rm ${degibbs_nii};	
		fi

		coreg_dir="${BIGGUS_DISKUS}/co_reg_${id}_m${zeros}-results/";
		if [[ -d ${coreg_dir} ]];then
			rm -r ${coreg_dir%results\/}*;	
		fi
		
		
	fi
	###
	# 5. Bias field correction (optional but recommended)
	stage='05';
	debiased=${work_dir}/${id}_${stage}_dwi_nii4D_biascorrected.mif
	mask_string=' ';
	if [[ -f ${tmp_mask} ]];then
		mask_string=" -mask ${temp_mask} ";
	fi
	if [[ ! -f ${debiased} ]];then
		dwibiascorrect ants ${preprocessed} ${debiased} -scratch ${work_dir}/
	fi
	
	if [[ ! -f ${debiased} ]];then
		echo "Process died during stage ${stage}" && exit 1;
	elif ((${cleanup}));then
		if [[ -f ${preprocessed} ]];then
			rm ${preprocessed};
		fi
		
		if [[ -f ${temp_mask} ]];then
			rm ${temp_mask};
		fi
	fi
else
	echo "Debiased mif file already exists; skipping to Stage ${pds_plus_one}." 
fi


###
# 6. Extract b0 and dwi from debiased nii4D
stage='06';

b0=${work_dir}/${id}_b0.nii.gz;
dwi=${work_dir}/${id}_dwi.nii.gz;

shells=$(mrinfo -shell_bvalues ${debiased});
# We remove the first shell, assuming it is the B0 value.
# shells=${shells#*\ };
# Trim trailing space.
shells=${shells%\ };

shellmeans=${work_dir}/${id}_shellmeans.mif;	
if [[ ! -f ${b0} || ! -f ${dwi} ]];then
	if [[ ! -f ${shellmeans} ]]; then
		dwishellmath ${debiased} mean ${shellmeans};
	fi
	
	i=0;
	for shelly_long in ${shells};do
		if (($i));then
			c_image="${work_dir}/${id}_dwi_b${shelly_long}.nii.gz";
		else
			c_image="${work_dir}/${id}_b0.nii.gz";
		fi	
		
		if [[ ! -e ${c_image} ]];then
			mrconvert ${shellmeans} -coord 3 ${i} -axes 0,1,2 ${c_image};
		fi
		let "i++";
	done
	
	dwi_stack_mif="${work_dir}/${id}_dwi_stack.mif";
	
	if [[ ! -f ${dwi} ]];then 
		if [[ $i -eq 2 ]];then
			mv ${c_image} ${dwi};
		else
			if [[ ! -f ${dwi_stack_mif} ]];then
				s_idc=$(mrinfo -shell_indices ${debiased});
				s_idc=${s_idc#*\ };
				s_idc=${s_idc%\ };
				s_idc=${s_idc// /,};
			
				mrconvert ${debiased} ${dwi_stack_mif} -coord 3 ${s_idc};
			fi
			mrmath ${dwi_stack_mif} mean ${dwi} -axis 3;
			
			if [[ ! -f ${dwi} ]];then
				echo "Process died during stage ${stage}" && exit 1;
			elif ((${cleanup}));then
				if [[ -f ${dwi_stack_mif} ]];then
					rm ${dwi_stack_mif};
				fi
			fi
			
			if [[ ! -f ${b0} ]];then
				echo "Process died during stage ${stage}" && exit 1;
			elif ((${cleanup}));then
				if [[ -f ${shellmeans} ]];then
					rm ${shellmeans};
				fi
			fi
		fi
	fi
fi

if [[ ! -f ${b0} || ! -f ${dwi} ]];then
	echo "Process died during stage ${stage}" && exit 1;
elif ((${cleanup}));then
	if [[ -f ${shellmeans} ]];then
		rm ${shellmeans};
	fi
	if [[ -f ${dwi_stack_mif} ]];then
		rm ${dwi_stack_mif};
	fi
fi


# With b0 in hand, generate a mask with fsl's bet:
mask=${work_dir}/${id}_mask.nii.gz;
if [[ ! -f ${mask} ]];then
	if [[ -f ${b0} ]];then
		bet ${b0} ${mask%_mask.nii.gz} -m -n;
		fslmaths ${mask} -add 0 ${mask} -odt "char";
	fi
fi

if [[ ! -f ${mask} ]];then
	echo "Process died during stage ${stage}" && exit 1;
fi



###
# 7. Fit the tensor model
stage='07';

strides=${work_dir}/${id}_strides.txt
if [[ ! -f $strides ]];then
	mrinfo -strides ${debiased} > $strides;
fi
dt=${work_dir}/${id}_${stage}_dt.mif;
if [[ ! -f ${dt} || ! -f ${b0} ]];then
	dwi2tensor ${debiased} ${dt} -mask ${mask};
fi

if [[ ! -f ${dt} ]];then
	echo "Process died during stage ${stage}" && exit 1;
fi
###
# 8. Compute FA (and other metrics, if desired)
stage='08';
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
# 9. Convert FA (or other metrics) to NIfTI for visualization
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
# 10. Estimating the response functions
stage='10';
wm_txt=${work_dir}/${id}_wm.txt;
gm_txt=${work_dir}/${id}_gm.txt;
csf_txt=${work_dir}/${id}_csf.txt;
voxels_mif=${work_dir}/${id}_voxels.mif.gz

if [[ ! -f ${wm_txt} || ! -f ${gm_txt} || ! -f ${csf_txt} || ! -f ${voxels_mif} ]];then
	dwi2response dhollander ${debiased} ${wm_txt} ${gm_txt} ${csf_txt} -voxels ${voxels_mif} -mask ${mask} -scratch ${work_dir};
fi

if [[ ! -f ${wm_txt} || ! -f ${gm_txt} || ! -f ${csf_txt} || ! -f ${voxels_mif} ]];then
	echo "Process died during stage ${stage}" && exit 1;
fi

###
# 11. Applying the basis functions to the diffusion data:
stage='11';
wmfod_mif=${work_dir}/${id}_wmfod.mif.gz;
gmfod_mif=${work_dir}/${id}_gmfod.mif.gz;
csffod_mif=${work_dir}/${id}_csffod.mif.gz;

if [[ ! -f ${wmfod_mif} ]];then
	dwi2fod msmt_csd ${debiased} -mask ${mask} ${wm_txt} ${wmfod_mif};
fi

if [[ ! -f ${wmfod_mif} ]];then
	echo "Process died during stage ${stage}" && exit 1;
fi

###
# 12. Normalize the FODs:
stage='12';
wmfod_norm_mif=${work_dir}/${id}_wmfod_norm.mif.gz
#gmfod_norm_mif=${work_dir}/${id}_gmfod_norm.mif.gz
#csffod_norm_mif=${work_dir}/${id}_csffod_norm.mif,gz  
if [[ ! -f ${wmfod_norm_mif} ]];then
	mtnormalise ${wmfod_mif} ${wmfod_norm_mif} -mask ${mask};
fi

if [[ ! -f ${wmfod_norm_mif} ]];then
	echo "Process died during stage ${stage}" && exit 1;
fi

###
# 13. Creating streamlines with tckgen
stage='13';
tracks_10M_tck=${work_dir}/${id}_tracks_10M.tck;
smaller_tracks=${work_dir}/${id}_smaller_tracks_2M.tck;
if [[ ! -f ${smaller_tracks} ]];then
	if [[ ! -f ${tracks_10M_tck} ]];then
		tckgen -backtrack -seed_image ${mask} -maxlength 1000 -cutoff 0.1 -select 10000000 ${wmfod_norm_mif} ${tracks_10M_tck} -nthreads 10;
	fi
	
	if [[ ! -f ${tracks_10M_tck} ]];then
		echo "Process died during stage ${stage}" && exit 1;
	fi
	###
	# 14. Extracting a subset of tracks.
	stage='14';
	tckedit ${tracks_10M_tck} -number 2000000 -minlength 0.1 ${smaller_tracks};
fi

if [[ ! -f ${smaller_tracks} ]];then
	echo "Process died during stage ${stage}" && exit 1;
elif ((${cleanup}));then
	if [[ -f ${tracks_10M_tck}  ]];then
		rm ${tracks_10M_tck};
	fi
fi
###
# 14.5 Further reducing tracks solely for QA visualization purpose.
stage=14.5;
QA_tracks=${work_dir}/${id}_QA_tracks_50k.tck;
if [[ ! -f ${QA_tracks} ]];then
	tckedit ${smaller_tracks} ${QA_tracks} -number 50000 -nthreads 10;
fi

if [[ ! -f ${QA_tracks} ]];then
	echo "NON-CRITICAL FAILURE: no QA_tracks were produced during stage ${stage}." ;
	echo "   Missing file: ${QA_tracks} ." ;
fi

###
# 15. Sifting the tracks with tcksift2: bc some wm tracks are over or underfitted
stage='15';
sift_mu_txt=${work_dir}/${id}_sift_mu.txt;
sift_coeffs_txt=${work_dir}/${id}_sift_coeffs.txt;
sift_1M_txt=${work_dir}/${id}_sift_1M.txt;

if [[ ! -f  ${sift_mu_txt} || ! -f ${sift_coeffs_txt} || ! -f ${sift_1M_txt} ]];then
	tcksift2  -out_mu ${sift_mu_txt} -out_coeffs ${sift_coeffs_txt} ${smaller_tracks} ${wmfod_norm_mif} ${sift_1M_txt} ;
fi

if [[ ! -f  ${sift_mu_txt} || ! -f ${sift_coeffs_txt} || ! -f ${sift_1M_txt} ]];then
	echo "Process died during stage ${stage}" && exit 1;
fi

###
# 16. Convert and remap IIT labels
stage='16';

labels=${work_dir}/${id}_IITmean_RPI_labels.nii.gz;

if [[ ! -e ${labels} ]];then
	source_labels=${BIGGUS_DISKUS}/../mouse/VBM_25ADNI01_IITmean_RPI-results/connectomics/${id}/${id}_IITmean_RPI_labels.nii.gz;
	if [[ -e ${source_labels} ]];then
		cp ${source_labels} ${labels};
	fi
	if [[ ! -e ${labels} ]];then
		echo "Process stopped at ${stage}.";
		echo "SAMBA labels do not exist yet."
		echo "Please run samba-pipe and backport the labels to this folder." && exit 0;
	fi
fi

parcels_mif=${work_dir}/${id}_IITmean_RPI_parcels.mif.gz;

if [[ ! -f ${parcels_mif} ]];then
	mrconvert ${labels} ${parcels_mif};
fi
	
max_label=$(mrstats -output max ${parcels_mif} | cut -d ' ' -f1);

if [[ max_label -gt 84 ]];then
	index2=(8 10 11 12 13 17 18 26 47 49 50 51 52 53 54 58 1001 1002 1003 1005 1006 1007 1008 1009 1010 1011 1012 1013 1014	1015 1016 1017 1018 1019 1020 1021 1022 1023 1024 1025 1026 1027 1028 1029 1030 1031 1032 1033 1034 1035 2001 2002 2003 2005 2006 2007 2008 2009 2010 2011 2012 2013 2014 2015 2016 2017 2018 2019 2020 2021 2022 2023 2024 2025 2026 2027 2028 2029 2030 2031 2032 2033 2034 2035);
	decomp_parcels=${parcels_mif%\.gz};
	if [[ ! -f ${decomp_parcels} ]];then
		gunzip ${parcels_mif};
	fi 

	for i in $(seq 1 84);do
		mrcalc ${decomp_parcels} ${index2[$i-1]} $i -replace ${decomp_parcels} -force;
	done
	if [[ ! -f ${parcels_mif} ]];then
		gzip ${decomp_parcels};
	fi 
fi

max_label=$(mrstats -output max ${parcels_mif} | cut -d ' ' -f1);
if [[ ${max_label} -gt 84 ]];then
	echo "Process died during stage ${stage}" && exit 1;
fi



###
# 17. Calculate connectomes
stage='17';
conn_folder=/mnt/newStor/paros//paros_WORK/ADNI_connectomics/${id}_connectomics;
if ((! $use_fsl));then
	conn_folder=/mnt/newStor/paros//paros_WORK/ADNI_connectomics/${id}_with_coreg_connectomics;
fi
if [[ ! -d ${conn_folder} ]];then
	mkdir ${conn_folder};
fi

distances_csv=${conn_folder}/${id}_distances.csv;
if [[ ! -f ${distances_csv} ]];then
	tck2connectome ${smaller_tracks} ${parcels_mif} ${distances_csv} -zero_diagonal -symmetric -scale_length -stat_edge  mean;
fi


mean_FA_per_streamline=${conn_folder}/${id}_per_strmline_mean_FA.csv;


if [[ ! -f ${mean_FA_per_streamline} ]];then
	tcksample ${smaller_tracks} ${fa_nii} ${mean_FA_per_streamline} -stat_tck mean;
fi

mean_FA_connectome=${conn_folder}/${id}_mean_FA_connectome.csv;
if [[ ! -f ${mean_FA_connectome} ]];then
	tck2connectome ${smaller_tracks} ${parcels_mif} ${mean_FA_connectome} -zero_diagonal -symmetric -scale_file ${mean_FA_per_streamline} -stat_edge mean;
fi



###
# 18.
stage='18';

# I think we decided we didn't want/need this first flavor
#parcels_csv=${conn_folder}/${id}_conn_sift_node.csv;
#assignments_parcels_csv=${conn_folder}/${id}_assignments_con_sift_node.csv;
#os.system('tck2connectome -symmetric -zero_diagonal -scale_invnodevol -tck_weights_in '+ sift_1M_txt+ ' '+ smallerTracks + ' '+ parcels_mif + ' '+ parcels_csv + ' -out_assignment ' + assignments_parcels_csv + ' -force')


parcels_csv_2=${conn_folder}/${id}_onn_plain.csv;
assignments_parcels_csv2=${conn_folder}/${id}_assignments_con_plain.csv;
if [[ ! -f ${parcels_csv_2} ||  ! -f ${assignments_parcels_csv2} ]];then
	tck2connectome -symmetric -zero_diagonal ${smaller_tracks} ${parcels_mif} ${parcels_csv_2} -out_assignment ${assignments_parcels_csv2} -force;
fi

parcels_csv_3=${conn_folder}/${id}_onn_sift.csv;
assignments_parcels_csv3=${conn_folder}/${id}_assignments_con_sift.csv;
if [[ ! -f ${parcels_csv_3} ||  ! -f ${assignments_parcels_csv3} ]];then
	tck2connectome -symmetric -zero_diagonal -tck_weights_in ${sift_1M_txt} ${smaller_tracks} ${parcels_mif} ${parcels_csv_3} -out_assignment ${assignments_parcels_csv3} -force;
fi

echo "The ${proc_name}_${id} pipeline has completed! Thanks for patronizing this wonderful script!" && exit 0
#######
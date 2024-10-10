#! /bin/env/bash

BD=/mnt/munin2/;
if [[ ! -e "${BD}Badea" ]];then
	BD=/Volumes/Data/;
fi

GD=${GUNNIES}
if [[ ! -e "${GD}" ]];then
	GD=/mnt/clustertmp/common/rja20_dev/gunnies/
	if [[ ! -e "${GD}" ]];then
		GD=~/Documents/MATLAB/gunnies/
	fi
fi


slurm=$(which sbatch 2>/dev/null |wc -l | tr -d [:space:])

if (($slurm));then
	submitter=${GD}/submit_slurm_cluster_job.bash
else
	submitter=${GD}/submit_sge_cluster_job.bash
fi

contrast=T1
protocol=MPRAGE
spin_me_round=0;
upper_dir="${BD}Badea/ADdecode.01/Data/Anat/";
SAMBA_dir="${BD}Badea/Lab/mouse/VBM_21ADDecode03_IITmean_RPI_fullrun-inputs/"
#for runno in $(ls -d ${upper_dir} 2*/);do
for runno in 01912;do
	runno=${runno##*_};
	runno=${runno/\//};
	Srunno="S${runno/\//}";
	for bxh in $(ls ${upper_dir}/*${runno}/*_0??.bxh);do
		test=$(grep -i ${protocol} ${bxh} 2>/dev/null | wc -l);
		if (($test));then
			nii=${bxh/bxh/nii\.gz};
			
			SAMBA_input=${SAMBA_dir}/${Srunno}_${contrast}.nii.gz;
			#ref=${SAMBA_dir/${Srunno}}
			#antsApplyTransforms -v 1 -d 3  -i ${nii} -r ${ref} -n BSpline -o ${new_nii};
			
			
			#SAMBA_input="/Volumes/Data/Badea/Lab/mouse/ADDeccode_symlink_pool2/S${runno}_T1.nii.gz";
			if [[ ! -e ${SAMBA_input} ]];then
				biac_dwi=$(ls -S ${BD}/Badea/ADdecode.01/Data/Anat/*_${runno}/*nii.gz | head -1);
				qial_T1=$nii
				qial_dwi="${BD}Badea/Lab/mouse/ADDeccode_symlink_pool2/${Srunno}_mrtrixfa.nii.gz";
				if [[ ! -e ${qial_dwi} ]];then
				#	qial_dwi="/mnt/munin2/Badea/Lab/mouse/ADDeccode_symlink_pool2/S${runno}_subjspace_fa.nii.gz";
				#	if [[ ! -e ${qial_dwi} ]];then
				#		qial_dwi="/mnt/munin2/Badea/Lab/human/AD_Decode/diffusion_prep_locale/diffusion_prep_S${runno}/S${runno}_subjspace_fa.nii.gz";
				#		if [[ ! -e ${qial_dwi} ]];then
							echo "FAILURE: Cannot find and FA image for runno: ${Srunno}" && exit 1;
				#		fi
				#	fi
				fi
				
				temp_dir="${BD}Badea/Lab/mouse/QSM_processed_7Dec2021/${runno}_tmp_dir";
				if [[ ! -d ${temp_dir} ]];then
					mkdir -m 775 ${temp_dir};
				fi
				
				t_vol1="${temp_dir}/${runno}_vol1.nii.gz";
				reslice_out="${temp_dir}/${Srunno}_${contrast}_resliced.nii.gz";
				better_header="${temp_dir}/${Srunno}_${contrast}_resliced_better_header.nii.gz";
				almost_there="${temp_dir}/${Srunno}_${contrast}_almost_there.nii.gz";
				if [[ ! -e ${SAMBA_input} ]];then
					if [[ ! -f ${almost_there} ]];then
						if [[ ! -f ${better_header} ]];then
							if [[ ! -f ${reslice_out} ]];then
								if [[ ! -f ${tvol_1} ]];then            
									# Extract first volume from BIAC diffusion nii4D:
									
									ExtractSliceFromImage 4 ${biac_dwi} ${t_vol1} 3 0 0;
									
								fi
								# Reslice T1 into that first DWI volume:
								antsApplyTransforms -v 1 -d 3  -i ${qial_T1} -r ${t_vol1} -n BSpline -o ${reslice_out};
							fi
				
							if (($spin_me_round));then
								# Splice header from qial_dwi on to the resliced data,
								# Needed if we had to rotate: final header splice:
								${GD}/nifti_header_splicer.bash ${qial_dwi} ${reslice_out} ${better_header}
							fi
						fi
						if (($spin_me_round));then
							## POSSIBLY OPTIONAL--MANUALLY CHECK IMAGES FOR INCONSISTENCIES!
							# Rotate 180 degrees around z-axis:
							if [[ -e /mnt/clustertmp/common/rja20_dev//matlab_execs_for_SAMBA// ]];then
								/mnt/clustertmp/common/rja20_dev//matlab_execs_for_SAMBA//img_transform_executable/run_img_transform_exec.sh /mnt/clustertmp/common/rja20_dev//MATLAB2015b_runtime/v90 ${better_header} LPS RAS ${almost_there};
							else
							echo Unable to run command: /mnt/clustertmp/common/rja20_dev//matlab_execs_for_SAMBA//img_transform_executable/run_img_transform_exec.sh /mnt/clustertmp/common/rja20_dev//MATLAB2015b_runtime/v90 ${better_header} LPS RAS ${almost_there};
							fi
						fi
					fi  
				 
					if (($spin_me_round));then
						${GD}/nifti_header_splicer.bash ${qial_dwi} ${almost_there} ${SAMBA_input};
					else
						${GD}/nifti_header_splicer.bash ${qial_dwi} ${reslice_out} ${SAMBA_input};
					fi
				fi
			fi
			masked_T1=${BD}/Badea/Lab/mouse/VBM_21ADDecode03_IITmean_RPI_fullrun-work/preprocess/${Srunno}_T1_masked.nii.gz
			cmd_1="/mnt/clustertmp/common/rja20_dev//matlab_execs_for_SAMBA//img_transform_executable/run_img_transform_exec.sh /mnt/clustertmp/common/rja20_dev//MATLAB2015b_runtime/v90 ${BD}/Badea/Lab/mouse/VBM_21ADDecode03_IITmean_RPI_fullrun-inputs/${Srunno}_T1.nii.gz RPI RPI ${BD}/Badea/Lab/mouse/VBM_21ADDecode03_IITmean_RPI_fullrun-work/preprocess/;"
			cmd_2="fslmaths ${BD}/Badea/Lab/mouse/VBM_21ADDecode03_IITmean_RPI_fullrun-work/preprocess/${Srunno}_T1.nii.gz -mas ${BD}Badea/Lab/mouse/VBM_21ADDecode03_IITmean_RPI_fullrun-work/preprocess/${Srunno}_mask.nii.gz ${masked_T1} -odt 'input';if [[ -f ${masked_T1} ]];then rm ${BD}/Badea/Lab/mouse/VBM_21ADDecode03_IITmean_RPI_fullrun-work/preprocess/${Srunno}_T1.nii.gz;fi"
			if [[ ! -e ${masked_T1} ]];then
				job_name="reorient_and_mask_${Srunno}_T1"
				sbatch_dir="${BD}Badea/Lab/mouse/VBM_21ADDecode03_IITmean_RPI_fullrun-work/preprocess/sbatch"
				cmd="${submitter} ${sbatch_dir} ${job_name} 0 0 ${cmd_1}${cmd_2}";
				$cmd;
			fi
		fi
	done	
done
#! /bin/env/bash
spin_me_round=0;
upper_dir="/Volumes/Data/Badea/ADdecode.01/Data/Anat/";
SAMBA_dir="/Volumes/Data/Badea/Lab/mouse/VBM_21ADDecode03_IITmean_RPI_fullrun-inputs/"
#for runno in $(ls -d ${upper_dir} 2*/);do
for runno in 01912;do
	runno=${runno##*_};
	runno=${runno/\//};
	Srunno="S${runno/\//}";
	for bxh in $(ls ${upper_dir}/*${runno}/*_0??.bxh);do
		test=$(grep -i MPRAGE ${bxh} 2>/dev/null | wc -l);
		if (($test));then
			nii=${bxh/bxh/nii\.gz};
			echo $nii;
			SAMBA_input=${SAMBA_dir}/${Srunno}_T1.nii.gz;
			#ref=${SAMBA_dir/${Srunno}}
			#antsApplyTransforms -v 1 -d 3  -i ${nii} -r ${ref} -n BSpline -o ${new_nii};
			
			
			SAMBA_input="/mnt/munin2/Badea/Lab/mouse/ADDeccode_symlink_pool2/S${runno}_QSM.nii.gz";
			if [[ ! -e ${SAMBA_input} ]];then
				biac_dwi=$(ls -S /mnt/munin2/Badea/ADdecode.01/Data/Anat/*_${runno}/*nii.gz | head -1);
				qial_T1=$nii
				
				qial_dwi="/mnt/munin2/Badea/Lab/mouse/ADDeccode_symlink_pool2/S${runno}_mrtrixfa.nii.gz";
				if [[ ! -e ${qial_dwi} ]];then
				#	qial_dwi="/mnt/munin2/Badea/Lab/mouse/ADDeccode_symlink_pool2/S${runno}_subjspace_fa.nii.gz";
				#	if [[ ! -e ${qial_dwi} ]];then
				#		qial_dwi="/mnt/munin2/Badea/Lab/human/AD_Decode/diffusion_prep_locale/diffusion_prep_S${runno}/S${runno}_subjspace_fa.nii.gz";
				#		if [[ ! -e ${qial_dwi} ]];then
							echo "FAILURE: Cannot find and FA image for runno: ${runno}" && exit 1;
				#		fi
				#	fi
				fi
				
				temp_dir="/mnt/munin2/Badea/Lab/mouse/QSM_processed_7Dec2021/${runno}_tmp_dir";
				if [[ ! -d ${temp_dir} ]];then
					mkdir -m 775 ${temp_dir};
				fi
				
				t_vol1="${temp_dir}/${runno}_vol1.nii.gz";
				reslice_out="${temp_dir}/${runno}_resliced.nii.gz";
				better_header="${temp_dir}/${runno}_resliced_better_header.nii.gz";
				almost_there="${temp_dir}/${runno}_almost_there.nii.gz";
				
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
								/mnt/clustertmp/common/rja20_dev/gunnies/nifti_header_splicer.bash ${qial_dwi} ${reslice_out} ${better_header}
							fi
						fi
						if (($spin_me_round));then
							## POSSIBLY OPTIONAL--MANUALLY CHECK IMAGES FOR INCONSISTENCIES!
							# Rotate 180 degrees around z-axis:
							/mnt/clustertmp/common/rja20_dev//matlab_execs_for_SAMBA//img_transform_executable/run_img_transform_exec.sh /mnt/clustertmp/common/rja20_dev//MATLAB2015b_runtime/v90 ${better_header} LPS RAS ${almost_there};
						fi
					fi  
				 
					if (($spin_me_round));then
						/mnt/clustertmp/common/rja20_dev/gunnies/nifti_header_splicer.bash ${qial_dwi} ${almost_there} ${SAMBA_input};
					else
						/mnt/clustertmp/common/rja20_dev/gunnies/nifti_header_splicer.bash ${qial_dwi} ${reslice_ou} ${SAMBA_input};
					fi
				fi
			fi
		fi
	done	
done 
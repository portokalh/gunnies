#! /bin/env/bash


contrast=T1
protocol=MPRAGE
spin_me_round=1;


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

upper_dir="${BD}Badea/ADdecode.01/Data/Anat/";
SAMBA_dir="${BD}Badea/Lab/mouse/VBM_21ADDecode03_IITmean_RPI_fullrun-inputs/"
sbatch_dir=${SAMBA_dir}sbatch;
if [[ -d ${sbatch_dir} ]];then
	mmkdir -m 775 ${sbatch_dir};
fi

for runno in $(ls -d ${upper_dir}2*/);do
	runno=${runno##*_};
	runno=${runno/\//};
	Srunno="S${runno/\//}";
	
	job_name=${Srunno}_register_and_reslice_T1_image
	cmd_1="${GD}/reslice_ADDecode_single_T1_slice_for_SAMBA.bash ${runno}"
	cmd="${submitter} ${sbatch_dir} ${job_name} 0 0 ${cmd_1}";
done
	
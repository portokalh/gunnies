#! /bin/env bash

## 28 October 2024 (Tues), BJA
# For use on the QIAL cluster

input_cmd=$1;

sbatch_dir="~/sbatch";
if [[ ! -d ${sbatch_dir} ]];then
	mkdir -m 775 ${sbatch_dir};
fi

timestamp=$(date +%Y%m%d%H%M.%S);
job_name=${USER}_${timestamp};
cmd="${GUNNIES}submit_slurm_cluster_job.bash ${sbatch_dir} ${job_name} 0 0 ${input_cmd}";
#echo $cmd;
$cmd;


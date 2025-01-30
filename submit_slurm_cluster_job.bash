#!/bin/bash

# This function creates a base bash script with SLURM cluster parameters.
# After that, it will submit it to the cluster, recording the job id number.
# Finally, it will rename the bash file with the job id prepended to it.

# It will look for an environment variable "$NOTIFICATION_EMAIL" to send job notifications to.
# If this is not set, it will default to ${USER}@duke.edu.

# NOTE: It is often valuable to capture the JOB_ID assigned to the cluster job
# produced by this script, and stored as a variable. This is particular useful
# for job dependencies (holds).
# In order to effectively capture this, use the following 2 lines of code--adjusting as needed:
# sub_command="/path/to/this/script/submit_slurm_cluster_job.bash arg1 arg2 arg3 etc";
# job_id=$(${sub_command} | tail -1 | cut -d ';' -f1 | cut -d ' ' -f4);

args=("$@");

sbatch_folder=${args[0]};
name=${args[1]};
memory=${args[2]}; # Use 0 to default to '50000M'
hold_jobs=${args[3]}; # Use 0 to default to no jobs to wait for.
cmd=${args[4]};
i="5";
arg_i=$#;

while [ $i -lt ${arg_i} ];do
    cmd="${cmd} ${args[$i]}";
    i=$[$i+1]
done

if [[ ! -d ${sbatch_folder} ]];then
	mkdir -m 775 ${sbatch_folder};
fi

sbatch_file="${sbatch_folder}/${name}.bash";
## Emails will probably fail for now, due to mismatch between $USER and Duke NetID
## Unless user  has NOTIFICATION_EMAIL set in env
if [[ "x${NOTIFICATION_EMAIL}x" == "xx" ]];then
    email="${USER}@duke.edu";
else
    email=${NOTIFICATION_EMAIL};
fi

if [[ "x${memory}x" == "x0x" ]];then
    memory='5000M';
fi

echo "#!/bin/bash" > ${sbatch_file};
if [[ "x${memory}x" != "x0x" ]];then
	echo "#SBATCH --mem=$memory" >> ${sbatch_file};
fi
echo "#SBATCH --mail-user=${email}" >> ${sbatch_file};
echo "#SBATCH --mail-type=END,FAIL" >> ${sbatch_file}; 
echo "#SBATCH --output=${sbatch_folder}/slurm-%j.out" >> ${sbatch_file};
echo "#SBATCH --error=${sbatch_folder}/slurm-%j.out" >> ${sbatch_file};
echo "#SBATCH --job-name=${name}" >> ${sbatch_file};
echo "#SBATCH --partition=normal" >> ${sbatch_file};
if [[ "x${hold_jobs}x" != "xx" ]] && [[ "x${hold_jobs}x" != "x0x" ]];then
	# afterok is the default condition for hold jobs. This can cause problems if 
	# preceding jobs complete before this job can be dispatched. (use 'afterany' instead)
	if [[ ! ${hold_jobs:0:3} == "aft" &&  ! ${hold_jobs:0:3} == "sin" ]];then
		hold_jobs="afterok:${hold_jobs}";
	fi
    echo "#SBATCH --dependency=${hold_jobs}" >> ${sbatch_file};
fi

# 25 January 2022, RJA: If things break, look here, where I added the '-e' option
echo -e "${cmd}" >> ${sbatch_file};

sub_cmd="sbatch ${sbatch_file}";
#sub_cmd="qsub -terse -V ${sbatch_file}";   

echo $sub_cmd;

job_id=$(${sub_cmd} | cut -d ' ' -f 4)
echo "JOB ID = ${job_id}; Job Name = ${name}";

#new_sbatch_file=${sbatch_file/${name}/${job_id}_${name}};
new_sbatch_file="${sbatch_folder}/${job_id}_${name}.bash";
# The first version of the "new_sbatch_file" code breaks down when we don't register to the first volume,
# as then name will look like "${runno}_m00", which will also appear in the *-inputs/work/results
# directories. Then it will try to sub in the first occurrence--the folder name--which doesn't exist.

mv ${sbatch_file} ${new_sbatch_file};
re='^[1-9]?[0-9]+$';
if [[ ${job_id} =~ $re ]];then
    exit_status=0;
else
    exit_status=1;
fi

exit "${exit_status}";

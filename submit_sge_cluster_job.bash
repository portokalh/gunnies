#!/bin/bash

# This function creates a base bash script with SGE cluster parameters.
# After that, it will submit it to the cluster, recording the job id number.
# Finally, it will rename the bash file with the job id prepended to it.

# It will look for an environment variable "$NOTIFICATION_EMAIL" to send job notifications to.
# If this is not set, it will default to ${USER}@duke.edu.

# NOTE: It is often valuable to capture the JOB_ID assigned to the cluster job
# produced by this script, and stored as a variable. This is particular useful
# for job dependencies (holds).
# In order to effectively capture this, use the following 2 lines of code--adjusting as needed:
# sub_command="/path/to/this/script/submit_sge_cluster_job.bash arg1 arg2 arg3 etc";
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

sbatch_file="${sbatch_folder}/${name}.bash";

if [[ "x${NOTIFICATION_EMAIL}x" == "xx" ]];then
    email="${USER}@duke.edu";
else
    email=${NOTIFICATION_EMAIL};
fi

if [[ "x${memory}x" == "x0x" ]];then
    memory='50000M';
fi



echo "#!/bin/bash" > ${sbatch_file};
echo "#\$ -l h_vmem=${memory},vf=${memory}" >> ${sbatch_file};
echo "#\$ -M ${email}" >> ${sbatch_file};
echo "#\$ -m ea" >> ${sbatch_file}; 
echo "#\$ -o ${sbatch_folder}"'/slurm-$JOB_ID.out' >> ${sbatch_file};
echo "#\$ -e ${sbatch_folder}"'/slurm-$JOB_ID.out' >> ${sbatch_file};
echo "#\$ -N ${name}" >> ${sbatch_file};

if [[ "x${hold_jobs}x" != "xx" ]] && [[ "x${hold_jobs}x" != "x0x" ]];then
    echo "#\$ -hold_jid ${hold_jobs}" >> ${sbatch_file};
fi

# 25 January 2022, RJA: If things break, look here, where I added the '-e' option
echo -e "${cmd}" >> ${sbatch_file};

sub_cmd="qsub -terse -V ${sbatch_file}";
    
echo $sub_cmd;

job_id=$($sub_cmd | tail -1);

echo "JOB ID = ${job_id}; Job Name = ${name}";

new_sbatch_file=${sbatch_file/${name}/${job_id}_${name}};

mv ${sbatch_file} ${new_sbatch_file};
re='^[1-9]?[0-9]+$';
if [[ ${job_id} =~ $re ]];then
    exit_status=0;
else
    exit_status=1;
fi

exit "${exit_status}";

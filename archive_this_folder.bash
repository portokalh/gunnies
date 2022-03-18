#! /bin/bash
if [[ ! $1 || $1 == "-h" ]];then
    echo "archive_this_folder: A simple script for archiving data on paros_DB."
    echo "Written 17 March 2022 (Thursday), BJ Anderson, Badea Lab, Duke University."
    echo "";
    echo "Usage:"
    echo "      bash archive_this_folder.bash \${type} \${project_code} \${source}"
    echo "Sample command:";
    echo "      bash archive_this_folder.bash \"VBA\" \"20.abb.15\" \"dwiMDT_NoNameYet_n32_1p5vox_smoothing-results\" ";
    echo "Note: If no source folder is specified, the current directory will be archived. Please use with caution."
    echo '';
    exit 0;
fi


type=$1;
project=$2;
src=$3;
target="/mnt/paros_DB/Projects/${project}/Analysis/${type}/"

hostname=$(hostname);
if [[ ${hostname:0:5} == 'blade' ]];then
    hostname="cluster.biac";
fi

if [[ ${src:0:1} != '/' ]];then
    src=${PWD}/${src};
fi

src=${src%%/};
echo "SOURCE = ${src}";
if [[ ! -d ${src} ]];then
    echo "ERROR: Could not find source directory: ${src}" && exit 1;
fi

if [[ ! $project ]];then
    echo "ERROR: No project code specified."
    echo "       Please use format: YY.project_name.project_number format."
    echo "       (18.abb.01, 19.anderson.03, etc etc etc)" && exit 1;
fi

if  [[ ! $type ]];then
    echo "ERROR: No data type specified."
    echo "       Please use a decscriptor with no spaces."
    echo "       ('VBA' 'VBA_ready_images' 'labels_and_stats' etc.)" && exit 1;
fi
debug=0;
if (($debug));then
    type="VBA";
    project="20.abb.15";
    src="${PWD}/dwiMDT_NoNameYet_n32_1p5vox_smoothing-results";
fi

target="/mnt/paros_DB/Projects/${project}/Analysis/${type}/"
log="${src}/${project}_${type}_archive.log";

cmd="rsync -blurtEDv --log-file=${log} ${src} alex@samos:${target}";

echo "This directory was transferred to paros_DB from $hostname on $(date) by ${USER}." > ${log};
echo "The following command was used:" >> ${log};
echo "#! /bin/bash" >> ${log};
echo "${cmd}" >> ${log};
echo "#" >> ${log};
echo "-----" >> ${log};
echo "Here is a snapshot of the contents at time of archiving:" >>  ${log};
${cmd} #| tee ${log};
#ls -al ${PWD}${src}/* >>  ${log};
echo '-----' >> ${log};
echo "END OF ARCHIVE LOG" >> ${log};
cmd_2="rsync -blurtEDv ${log} alex@samos:${target}";
echo "Transferring archive log to archive:" >> ${log};
echo "#! /bin/bash" >> ${log};
echo ${cmd_2} >> ${log};
${cmd_2};

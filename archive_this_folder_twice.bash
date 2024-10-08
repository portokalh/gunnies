#! /bin/bash
# Updated 19 May 2022, RJA
# Updated 3 June 2023, RJA
# Last updated 27 June 2023, RJA
if [[ ! $1 || $1 == "-h" ]];then
    echo "archive_this_folder: A simple script for simultaneously archiving data on paros_DB and dusom_mousebrains."
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

hostname=$(hostname);
if [[ ${hostname:0:5} == 'blade' ]];then
    hostname="cluster.biac";
fi

net_src=0;

net_test=$(tr -dc '@' <<<"${src}" | awk '{ print length; }');
if ((${net_test})); then
	net_src=1;
else
	if [[ ${src:0:1} != '/' ]];then
		src=${PWD}/${src};
	fi
fi

src=${src%%/};
echo "SOURCE = ${src}";
if ((${net_src}));then
	s_parent=${src%%:*}
	s_path=${src#*:};
	cmd="if [[ ! -e ${s_path} ]];then echo 1; else echo 0;fi"
	no_folder=$(ssh ${s_parent} "${cmd}");
	if ((${no_folder}));then
		echo "ERROR: Could not find source directory: ${src}" && exit 1;
	fi
else
	if [[ ! -d ${src} ]];then
		echo "ERROR: Could not find source directory: ${src}" && exit 1;
	fi
fi

if [[ ! $project ]];then
    echo "ERROR: No project code specified."
    echo "       Please use format: YY.project_name.project_number format."
    echo "       (18.abb.01, 19.anderson.03, etc etc etc)" && exit 1;
fi

if  [[ ! $type ]];then
    echo "ERROR: No data type specified."
    echo "       Please use a descriptor with no spaces."
    echo "       ('VBA' 'VBA_ready_images' 'labels_and_stats' etc.)" && exit 1;
fi



# Default archive directory is Analysis, but can be put under 'Data' if type=Data/${some_subtype}:

type_test=${type:0:4};
if [[ ${type_test} == 'Data' ]];then
	folder='Data'
	subtype=${type:5};
else
	folder='Analysis'
	subtype=${type};
fi

echo "Folder = ${folder}"
echo "subtype = ${subtype}"
target_2="alex@samos:/mnt/paros_DB/Projects/${project}/${folder}/${subtype}/";
target_1="/Volumes/dusom_mousebrains/All_Staff/Projects/${project}/${folder}/${subtype}/";



#######
# It is assumed that dusom_mousebrains has to be mounted. Test for this before beginning any work:
mnt_error=0;
mnt_error_msg='';#"ERROR: Please make sure the following volume(s) have been properly mounted:\n"
for target in ${target_1} ${target_2};do
	if [[ "x${target:0:4}x" == 'x/Volx' ]];then
		mnt_dir=${target#/Volumes/};
		mnt_dir=${mnt_dir%%/*};
		if [[ ! -e "/Volumes/${mnt_dir}" ]];then
			mnt_error=1;
			mnt_error_msg=$(echo "${mnt_error_msg}";echo "    ${mnt_dir}");
		fi 
	fi
done

if ((${mnt_error}));then
	echo "ERROR: Please make sure the following volume(s) have been properly mounted:${mnt_error_msg}" && exit 1;
fi


#######

debug=0;
if (($debug));then
    type="VBA";
    project="20.abb.15";
    src="${PWD}/dwiMDT_NoNameYet_n32_1p5vox_smoothing-results";
fi

#######

for target in ${target_2} ${target_1};do
t_parent=${target%/*}

if [[ "x${target:0:4}x" == 'x/Volx' ]];then
	if [[ ! -e ${t_parent} ]];then
		mkdir -p ${t_parent};
	fi 
else
	t_local=${t_parent##*:}
	cmd="echo ${t_local}; if [[ ! -e ${t_local} ]];then mkdir -p ${t_local};fi"
	ssh ${t_parent%%:*} "${cmd}";
fi

timestamp=$(date +%Y%m%d%H%M.%S);
log="${src}/${project}_${subtype}_${timestamp}_archive.log";

if ((${net_src}));then
	log=${PWD}/${project}_${subtype}_${timestamp}_archive.log;
fi
#cmd="rsync -blurtEDv  --log-file=${log} ${src} alex@samos:${target}";
cmd="rsync -blurtDv --log-file=${log} ${src} ${target}";


dual_remote_test=$(tr -dc '@' <<<"${cmd}" | awk '{ print length; }');

nickname=$(echo ${target} | cut -d '/' -f3);
echo "This directory was transferred to ${nickname} from $hostname on $(date) by ${USER}." > ${log};
echo "The following command was used:" >> ${log};
echo "#! /bin/bash" >> ${log};
echo "${cmd}" >> ${log};
echo "#" >> ${log};
echo "-----" >> ${log};
echo "Here is a snapshot of the contents at time of archiving:" >>  ${log};
if [[ ${dual_remote_test} -gt 1 ]];then
	echo "ERROR: Attempting to use rsync with 2 remote hosts; skipping for now. (command: ${cmd})" && continue;
	r_cmd="rsync -blurtDv --log-file=${log} ${src} ${target}";
	ssh -t ${t_parent%%:*} ${r_cmd};
else
	${cmd} #| tee ${log};
fi
#ls -al ${PWD}${src}/* >>  ${log};
echo '-----' >> ${log};
echo "END OF ARCHIVE LOG" >> ${log};
#cmd_2="rsync -blurtEDv ${log} alex@samos:${target}";
cmd_2="rsync -blurtDv ${log} ${target}";
echo "Transferring archive log to archive:" >> ${log};
echo "#! /bin/bash" >> ${log};
echo ${cmd_2} >> ${log};
${cmd_2};
if ((${net_src}));then
	rsync -blurtDv ${log} ${src};
	rm ${log};
fi
done

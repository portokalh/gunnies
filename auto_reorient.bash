#!/usr/bin/env bash

set -euo pipefail

############################################
# Defaults
############################################

transform_exec="/home/apps/matlab_execs_for_SAMBA/img_transform_executable/run_img_transform_exec.sh"
mcr="/home/apps/MATLAB2015b_runtime/v90"

############################################
# Usage
############################################

usage() {

cat <<EOF

Usage:
    $(basename "$0") \\
        --mask <mask.nii.gz> \\
        --orientation <ALS | reference_mask.nii.gz> \\
        --output_dir <output_dir> \\
        --files <file1,file2,file3>

Required:
    --mask
        Input mask used to determine current orientation

    --orientation
        Either:
            - valid 3-letter orientation (ALS, RPI, LPS, etc)
            - OR reference image/mask whose orientation will be inferred

    --output_dir
        Output directory

Optional:
    --files
        Comma-delimited list of additional files to reorient
        The mask itself is ALWAYS reoriented automatically

Examples:

    Explicit orientation:
    $(basename "$0") \\
        --mask brain_mask.nii.gz \\
        --orientation ALS \\
        --output_dir reoriented \\
        --files T2.nii.gz,DWI.nii.gz

    Reference image orientation:
    $(basename "$0") \\
        --mask brain_mask.nii.gz \\
        --orientation reference_mask.nii.gz \\
        --output_dir reoriented \\
        --files T2.nii.gz

EOF
}

############################################
# Validate orientation string
############################################

is_valid_orientation() {

    local orient="$1"

    [[ ${#orient} -eq 3 ]] || return 1

    local c1="${orient:0:1}"
    local c2="${orient:1:1}"
    local c3="${orient:2:1}"

    [[ "$c1" =~ [RL] ]] || return 1
    [[ "$c2" =~ [AP] ]] || return 1
    [[ "$c3" =~ [SI] ]] || return 1

    return 0
}

############################################
# Predict orientation helper
############################################

predict_orientation() {

    local img="$1"

    bash /home/apps/Find_Mouse_Brain_Orientation/modeling/predict_orientation.sh \
        "${img}" 2>/dev/null \
        | grep 'Predicted' \
        | cut -d ':' -f3 \
        | tr -d '[:blank:]'
}

############################################
# Parse arguments
############################################

mask=""
orientation_input=""
output_dir=""
files_csv=""

while [[ $# -gt 0 ]]; do

    case "$1" in

        --mask)
            mask="$2"
            shift 2
            ;;

        --orientation)
            orientation_input="$2"
            shift 2
            ;;

        --output_dir)
            output_dir="$2"
            shift 2
            ;;

        --files)
            files_csv="$2"
            shift 2
            ;;

        -h|--help)
            usage
            exit 0
            ;;

        *)
            echo "ERROR: Unknown argument:"
            echo "    $1"
            echo
            usage
            exit 1
            ;;

    esac

done

############################################
# Validate required args
############################################

if [[ -z "${mask}" ]]; then
    echo "ERROR: --mask is required"
    exit 1
fi

if [[ -z "${orientation_input}" ]]; then
    echo "ERROR: --orientation is required"
    exit 1
fi

if [[ -z "${output_dir}" ]]; then
    echo "ERROR: --output_dir is required"
    exit 1
fi

############################################
# Validate files
############################################

if [[ ! -f "${mask}" ]]; then
    echo "ERROR: Mask does not exist:"
    echo "    ${mask}"
    exit 1
fi

############################################
# Create output directory
############################################

mkdir -p "${output_dir}"

if [[ ! -d "${output_dir}" ]]; then
    echo "ERROR: Failed to create output directory:"
    echo "    ${output_dir}"
    exit 1
fi

############################################
# Determine input orientation
############################################

input_orientation=$(predict_orientation "${mask}")

if [[ -z "${input_orientation}" ]]; then
    echo "ERROR: Failed to determine orientation of mask:"
    echo "    ${mask}"
    exit 1
fi

echo
echo "Automatic input orientation found: ${input_orientation}"

############################################
# Determine output orientation
############################################

if [[ -f "${orientation_input}" ]]; then

    echo
    echo "Orientation reference image detected:"
    echo "    ${orientation_input}"

    output_orientation=$(predict_orientation "${orientation_input}")

    if [[ -z "${output_orientation}" ]]; then
        echo "ERROR: Failed to determine orientation from reference image:"
        echo "    ${orientation_input}"
        exit 1
    fi

    echo "Automatic output orientation found: ${output_orientation}"

else

    output_orientation="${orientation_input}"

    if ! is_valid_orientation "${output_orientation}"; then
        echo "ERROR: Invalid orientation:"
        echo "    ${output_orientation}"
        exit 1
    fi

    echo
    echo "Using explicit output orientation: ${output_orientation}"

fi

############################################
# Validate transform executable
############################################

if [[ ! -x "${transform_exec}" ]]; then
    echo "ERROR: Transform executable missing or not executable:"
    echo "    ${transform_exec}"
    exit 1
fi

############################################
# Build file list
############################################

declare -a files_to_process

files_to_process+=("${mask}")

if [[ -n "${files_csv}" ]]; then

    IFS=',' read -ra additional_files <<< "${files_csv}"

    for f in "${additional_files[@]}"; do

        f=$(echo "${f}" | xargs)

        [[ -z "${f}" ]] && continue

        if [[ ! -f "${f}" ]]; then
            echo "ERROR: Additional file does not exist:"
            echo "    ${f}"
            exit 1
        fi

        files_to_process+=("${f}")

    done

fi

############################################
# Reorient files
############################################

echo
echo "===================================================="
echo "Beginning reorientation"
echo "===================================================="

for infile in "${files_to_process[@]}"; do

    echo
    echo "Reorienting:"
    echo "    ${infile}"
    echo "FROM:"
    echo "    ${input_orientation}"
    echo "TO:"
    echo "    ${output_orientation}"

    "${transform_exec}" \
        "${mcr}" \
        "${infile}" \
        "${input_orientation}" \
        "${output_orientation}" \
        "${output_dir}/"

    outfile="${output_dir}/$(basename "${infile}")"

    echo
    echo "Output written to:"
    echo "    ${outfile}"

done

echo
echo "===================================================="
echo "Done"
echo "===================================================="
echo
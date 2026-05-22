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
        [--files <file1,file2,file3>]

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

    -h, --help
        Show this help message

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
# Error helper
############################################

die() {

    echo
    echo "ERROR: $1"
    echo

    usage

    exit 1
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

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

while [[ $# -gt 0 ]]; do

    case "$1" in

        --mask)

            [[ $# -ge 2 ]] || die "--mask requires an argument"

            mask="$2"
            shift 2
            ;;

        --orientation)

            [[ $# -ge 2 ]] || die "--orientation requires an argument"

            orientation_input="$2"
            shift 2
            ;;

        --output_dir)

            [[ $# -ge 2 ]] || die "--output_dir requires an argument"

            output_dir="$2"
            shift 2
            ;;

        --files)

            [[ $# -ge 2 ]] || die "--files requires an argument"

            files_csv="$2"
            shift 2
            ;;

        -h|--help)

            usage
            exit 0
            ;;

        *)

            die "Unknown argument: $1"
            ;;

    esac

done

############################################
# Validate required args
############################################

[[ -n "${mask}" ]] || die "--mask is required"

[[ -n "${orientation_input}" ]] || die "--orientation is required"

[[ -n "${output_dir}" ]] || die "--output_dir is required"

############################################
# Validate mask
############################################

[[ -f "${mask}" ]] || die "Mask does not exist: ${mask}"

############################################
# Create output directory
############################################

mkdir -p "${output_dir}"

[[ -d "${output_dir}" ]] || die "Failed to create output directory: ${output_dir}"

############################################
# Determine input orientation
############################################

input_orientation=$(predict_orientation "${mask}")

[[ -n "${input_orientation}" ]] || die "Failed to determine orientation of mask: ${mask}"

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

    [[ -n "${output_orientation}" ]] || \
        die "Failed to determine orientation from reference image: ${orientation_input}"

    echo "Automatic output orientation found: ${output_orientation}"

else

    output_orientation="${orientation_input}"

    is_valid_orientation "${output_orientation}" || \
        die "Invalid orientation: ${output_orientation}"

    echo
    echo "Using explicit output orientation: ${output_orientation}"

fi

############################################
# Validate transform executable
############################################

[[ -x "${transform_exec}" ]] || \
    die "Transform executable missing or not executable: ${transform_exec}"

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

        [[ -f "${f}" ]] || die "Additional file does not exist: ${f}"

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
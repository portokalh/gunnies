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
    Orientation detection only:
        $(basename "$0") -m brain_mask.nii.gz

    Reorientation:
        $(basename "$0") \\
            -m brain_mask.nii.gz \\
            -r ALS \\
            -o output_dir \\
            [-f file1,file2,file3]

Required:
    -m
        Input image used to determine current orientation

Optional:
    -r
        Reference orientation

        Can be either:
            - valid 3-letter orientation (ALS, RPI, LPS, etc)
            - OR reference image whose orientation will be inferred

    -o
        Output directory

    -f
        Comma-delimited list of additional files to reorient

        The input image itself is ALWAYS reoriented automatically.

    -h
        Show this help message

Behavior:
    If ONLY -m is provided:
        The script reports the detected orientation and exits.

    Images are automatically binarized using:
        fslmaths image -bin

    Binarized masks are checked to ensure they are not:
        - entirely zero
        - entirely one

Examples:

    Orientation detection only:
        $(basename "$0") -m brain_mask.nii.gz

    Explicit orientation:
        $(basename "$0") \\
            -m brain_mask.nii.gz \\
            -r ALS \\
            -o reoriented \\
            -f T2.nii.gz,DWI.nii.gz

    Reference image orientation:
        $(basename "$0") \\
            -m brain_mask.nii.gz \\
            -r reference_mask.nii.gz \\
            -o reoriented \\
            -f T2.nii.gz

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
# Cleanup
############################################

tmp_files=()

cleanup() {

    for f in "${tmp_files[@]:-}"; do

        [[ -f "${f}" ]] && rm -f "${f}"

    done
}

trap cleanup EXIT

############################################
# Validate orientation string
############################################

is_valid_orientation() {

    local orient
    orient=$(echo "$1" | tr '[:lower:]' '[:upper:]')

    [[ ${#orient} -eq 3 ]] || return 1

    local has_rl=0
    local has_ap=0
    local has_si=0

    for (( i=0; i<3; i++ )); do

        local char="${orient:$i:1}"

        case "${char}" in

            R|L)
                ((has_rl++))
                ;;

            A|P)
                ((has_ap++))
                ;;

            S|I)
                ((has_si++))
                ;;

            *)
                return 1
                ;;

        esac

    done

    [[ ${has_rl} -eq 1 ]] || return 1
    [[ ${has_ap} -eq 1 ]] || return 1
    [[ ${has_si} -eq 1 ]] || return 1

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
# Create temporary binary mask
############################################

prepare_temp_binary_mask() {

    local input_img="$1"

    echo
    echo "Generating temporary binary mask for:"
    echo "    ${input_img}"

    local tmpmask
    tmpmask=$(mktemp /tmp/orient_mask_XXXXXX.nii.gz)

    tmp_files+=("${tmpmask}")

    fslmaths "${input_img}" -bin "${tmpmask}"

    ########################################
    # Validate binary mask
    ########################################

    local minval
    local maxval

    read -r minval maxval <<< "$(fslstats "${tmpmask}" -R)"

    echo "Temporary mask value range:"
    echo "    min = ${minval}"
    echo "    max = ${maxval}"

    ########################################
    # Reject all-zero masks
    ########################################

    awk -v min="${minval}" -v max="${maxval}" '
    BEGIN {

        tol = 1e-6

        if (min > -tol && min < tol &&
            max > -tol && max < tol)
            exit 1

        exit 0
    }'

    if [[ $? -ne 0 ]]; then

        rm -f "${tmpmask}"

        die "Binarized image is entirely zero: ${input_img}"

    fi

    ########################################
    # Reject all-one masks
    ########################################

    awk -v min="${minval}" -v max="${maxval}" '
    BEGIN {

        tol = 1e-6

        if (min > 1-tol && min < 1+tol &&
            max > 1-tol && max < 1+tol)
            exit 1

        exit 0
    }'

    if [[ $? -ne 0 ]]; then

        rm -f "${tmpmask}"

        die "Binarized image is entirely one: ${input_img}"

    fi

    echo "Temporary orientation mask:"
    echo "    ${tmpmask}"

    echo "${tmpmask}"
}

############################################
# Parse arguments
############################################

mask=""
reference_orientation=""
output_dir=""
files_csv=""

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

while getopts ":m:r:o:f:h" opt; do

    case ${opt} in

        m)
            mask="${OPTARG}"
            ;;

        r)
            reference_orientation="${OPTARG}"
            ;;

        o)
            output_dir="${OPTARG}"
            ;;

        f)
            files_csv="${OPTARG}"
            ;;

        h)
            usage
            exit 0
            ;;

        :)
            die "Option -${OPTARG} requires an argument"
            ;;

        \?)
            die "Invalid option: -${OPTARG}"
            ;;

    esac

done

############################################
# Validate required args
############################################

[[ -n "${mask}" ]] || die "-m is required"

[[ -f "${mask}" ]] || \
    die "Input image does not exist: ${mask}"

############################################
# Validate dependencies
############################################

command -v fslmaths >/dev/null 2>&1 || \
    die "fslmaths not found in PATH"

command -v fslstats >/dev/null 2>&1 || \
    die "fslstats not found in PATH"

############################################
# Determine input orientation
############################################

input_mask=$(prepare_temp_binary_mask "${mask}")

input_orientation=$(predict_orientation "${input_mask}")

[[ -n "${input_orientation}" ]] || \
    die "Failed to determine input orientation"

echo
echo "Automatic input orientation found: ${input_orientation}"

############################################
# Orientation detection only mode
############################################

if [[ -z "${reference_orientation}" ]]; then

    echo
    echo "No reference orientation provided."
    echo "Orientation detection complete."
    echo

    exit 0

fi

############################################
# Determine output orientation
############################################

if [[ -f "${reference_orientation}" ]]; then

    echo
    echo "Reference orientation image detected:"
    echo "    ${reference_orientation}"

    ref_mask=$(prepare_temp_binary_mask "${reference_orientation}")

    output_orientation=$(predict_orientation "${ref_mask}")

    [[ -n "${output_orientation}" ]] || \
        die "Failed to determine orientation from reference image"

    echo
    echo "Automatic output orientation found: ${output_orientation}"

else

    output_orientation=$(echo "${reference_orientation}" | tr '[:lower:]' '[:upper:]')

    is_valid_orientation "${output_orientation}" || \
        die "Invalid orientation: ${output_orientation}"

    echo
    echo "Using explicit output orientation: ${output_orientation}"

fi

############################################
# Validate output dir requirement
############################################

[[ -n "${output_dir}" ]] || \
    die "-o output directory is required when using -r"

mkdir -p "${output_dir}"

[[ -d "${output_dir}" ]] || \
    die "Failed to create output directory: ${output_dir}"

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

        [[ -f "${f}" ]] || \
            die "Additional file does not exist: ${f}"

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
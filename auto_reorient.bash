#!/usr/bin/env bash

set -euo pipefail

transform_exec="/home/apps/matlab_execs_for_SAMBA/img_transform_executable/run_img_transform_exec.sh"
mcr="/home/apps/MATLAB2015b_runtime/v90"

usage() {
cat <<EOF

Usage:
    Orientation detection:
        $(basename "$0") -m image_or_mask.nii.gz

    Reorientation from detected orientation:
        $(basename "$0") -m image_or_mask.nii.gz -r ALS -o output_dir [-f file1,file2]

    Reorientation from explicit starting orientation:
        $(basename "$0") -m ALS -r PIR -o output_dir -f file1,file2

Options:
    -m
        Input image/mask used to determine starting orientation,
        OR explicit 3-letter starting orientation.

    -r
        Reference orientation:
            - explicit 3-letter orientation
            - OR image/mask whose orientation will be inferred

    -o
        Output directory

    -f
        Comma-delimited list of files to reorient

    -h
        Show help

EOF
}

die() {
    echo
    echo "ERROR: $1"
    echo
    usage
    exit 1
}

tmp_files=()

cleanup() {
    for f in "${tmp_files[@]:-}"; do
        [[ -f "$f" ]] && rm -f "$f"
    done
}

trap cleanup EXIT

is_valid_orientation() {
    local orient
    orient=$(echo "$1" | tr '[:lower:]' '[:upper:]')

    [[ ${#orient} -eq 3 ]] || return 1

    local has_rl=0
    local has_ap=0
    local has_si=0

    for (( i=0; i<3; i++ )); do
        local char="${orient:$i:1}"

        case "$char" in
            R|L) ((has_rl++)) ;;
            A|P) ((has_ap++)) ;;
            S|I) ((has_si++)) ;;
            *) return 1 ;;
        esac
    done

    [[ $has_rl -eq 1 && $has_ap -eq 1 && $has_si -eq 1 ]]
}

predict_orientation() {
    local img="$1"

    bash /home/apps/Find_Mouse_Brain_Orientation/modeling/predict_orientation.sh \
        "$img" 2>/dev/null \
        | grep 'Predicted' \
        | cut -d ':' -f3 \
        | tr -d '[:blank:]'
}

prepare_temp_binary_mask() {
    local input_img="$1"

    >&2 echo
    >&2 echo "Generating temporary binary mask for:"
    >&2 echo "    ${input_img}"

    local tmpmask
    tmpmask=$(mktemp /tmp/orient_mask_XXXXXX.nii.gz)
    tmp_files+=("$tmpmask")

    fslmaths "$input_img" -bin "$tmpmask"

    local minval
    local maxval
    read -r minval maxval <<< "$(fslstats "$tmpmask" -R)"

    >&2 echo "Temporary mask value range:"
    >&2 echo "    min = ${minval}"
    >&2 echo "    max = ${maxval}"

    if awk -v min="$minval" -v max="$maxval" '
        BEGIN {
            tol = 1e-6
            exit !(
                min > -tol && min < tol &&
                max > -tol && max < tol
            )
        }'
    then
        die "Binarized image is entirely zero: ${input_img}"
    fi

    if awk -v min="$minval" -v max="$maxval" '
        BEGIN {
            tol = 1e-6
            exit !(
                min > 1-tol && min < 1+tol &&
                max > 1-tol && max < 1+tol
            )
        }'
    then
        die "Binarized image is entirely one: ${input_img}"
    fi

    >&2 echo "Temporary orientation mask:"
    >&2 echo "    ${tmpmask}"

    echo "$tmpmask"
}

mask_or_orientation=""
reference_orientation=""
output_dir=""
files_csv=""

[[ $# -gt 0 ]] || {
    usage
    exit 1
}

while getopts ":m:r:o:f:h" opt; do
    case "$opt" in
        m) mask_or_orientation="$OPTARG" ;;
        r) reference_orientation="$OPTARG" ;;
        o) output_dir="$OPTARG" ;;
        f) files_csv="$OPTARG" ;;
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

[[ -n "$mask_or_orientation" ]] || die "-m is required"

command -v fslmaths >/dev/null 2>&1 || die "fslmaths not found in PATH"
command -v fslstats >/dev/null 2>&1 || die "fslstats not found in PATH"

declare -a files_to_process=()

if is_valid_orientation "$mask_or_orientation"; then

    input_orientation=$(echo "$mask_or_orientation" | tr '[:lower:]' '[:upper:]')

    echo
    echo "Using explicit starting orientation from -m: ${input_orientation}"

    [[ -n "$files_csv" ]] || \
        die "-f is required when -m is an explicit orientation"

else

    [[ -f "$mask_or_orientation" ]] || \
        die "-m must be either a valid orientation or an existing image: ${mask_or_orientation}"

    input_mask=$(prepare_temp_binary_mask "$mask_or_orientation")

    input_orientation=$(predict_orientation "$input_mask")

    [[ -n "$input_orientation" ]] || \
        die "Failed to determine input orientation"

    echo
    echo "Automatic input orientation found: ${input_orientation}"

    files_to_process+=("$mask_or_orientation")

fi

if [[ -z "$reference_orientation" ]]; then
    echo
    echo "No reference orientation provided."
    echo "Orientation detection complete."
    echo
    exit 0
fi

if [[ -f "$reference_orientation" ]]; then

    echo
    echo "Reference orientation image detected:"
    echo "    ${reference_orientation}"

    ref_mask=$(prepare_temp_binary_mask "$reference_orientation")

    output_orientation=$(predict_orientation "$ref_mask")

    [[ -n "$output_orientation" ]] || \
        die "Failed to determine orientation from reference image"

    echo
    echo "Automatic reference orientation found: ${output_orientation}"

else

    output_orientation=$(echo "$reference_orientation" | tr '[:lower:]' '[:upper:]')

    is_valid_orientation "$output_orientation" || \
        die "Invalid reference orientation: ${output_orientation}"

    echo
    echo "Using explicit reference orientation: ${output_orientation}"

fi

[[ -n "$output_dir" ]] || die "-o output directory is required when using -r"

mkdir -p "$output_dir"

[[ -d "$output_dir" ]] || die "Failed to create output directory: ${output_dir}"

[[ -x "$transform_exec" ]] || \
    die "Transform executable missing or not executable: ${transform_exec}"

if [[ -n "$files_csv" ]]; then

    IFS=',' read -ra additional_files <<< "$files_csv"

    for f in "${additional_files[@]}"; do
        f=$(echo "$f" | xargs)

        [[ -z "$f" ]] && continue

        [[ -f "$f" ]] || die "File does not exist: ${f}"

        files_to_process+=("$f")
    done

fi

[[ ${#files_to_process[@]} -gt 0 ]] || die "No files to reorient"

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

    "$transform_exec" \
        "$mcr" \
        "$infile" \
        "$input_orientation" \
        "$output_orientation" \
        "${output_dir}/"

    outfile="${output_dir}/$(basename "$infile")"

    echo
    echo "Output written to:"
    echo "    ${outfile}"

done

echo
echo "===================================================="
echo "Done"
echo "===================================================="
echo
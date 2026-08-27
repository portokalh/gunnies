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

Behavior:
    If -m is an image and no -r is provided:
        The image is binarized, its orientation is detected,
        and the orientation is reported.

    If -m is a 3-letter orientation:
        Files supplied with -f are assumed to start in that orientation.

    Any image used for orientation detection is first binarized
    using all nonzero voxels.

    The temporary binary mask must contain both 0 and 1.
    All-zero or all-one masks are rejected.

EOF
}

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
        [[ -f "$f" ]] && rm -f "$f"
    done
}

trap cleanup EXIT

############################################
# Validate SPIRAL orientation
############################################

is_valid_orientation() {
    local orient
    orient=$(echo "$1" | tr '[:lower:]' '[:upper:]')

    [[ ${#orient} -eq 3 ]] || return 1

    local has_rl=0
    local has_ap=0
    local has_si=0
    local char

    for (( i=0; i<3; i++ )); do
        char="${orient:$i:1}"

        case "$char" in
            R|L)
                ((has_rl+=1))
                ;;
            A|P)
                ((has_ap+=1))
                ;;
            S|I)
                ((has_si+=1))
                ;;
            *)
                return 1
                ;;
        esac
    done

    [[ $has_rl -eq 1 &&
       $has_ap -eq 1 &&
       $has_si -eq 1 ]]
}

############################################
# Predict orientation
############################################

predict_orientation() {
    local img="$1"

    bash /home/apps/Find_Mouse_Brain_Orientation/modeling/predict_orientation.sh \
        "$img" 2>/dev/null \
        | grep 'Predicted' \
        | cut -d ':' -f3 \
        | tr -d '[:blank:]'
}

############################################
# Generate temporary binary mask
############################################

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

    if [[ "$minval" == "0.000000" &&
          "$maxval" == "0.000000" ]]; then

        rm -f "$tmpmask"
        die "Binarized image is entirely zero: ${input_img}"
    fi

    if [[ "$minval" == "1.000000" &&
          "$maxval" == "1.000000" ]]; then

        rm -f "$tmpmask"
        die "Binarized image is entirely one: ${input_img}"
    fi

    >&2 echo "Temporary orientation mask:"
    >&2 echo "    ${tmpmask}"

    echo "$tmpmask"
}

############################################
# Parse arguments
############################################

mask_or_orientation=""
reference_orientation=""
output_dir=""
files_csv=""

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

while getopts ":m:r:o:f:h" opt; do
    case "$opt" in
        m)
            mask_or_orientation="$OPTARG"
            ;;
        r)
            reference_orientation="$OPTARG"
            ;;
        o)
            output_dir="$OPTARG"
            ;;
        f)
            files_csv="$OPTARG"
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
# Validate -m
############################################

[[ -n "$mask_or_orientation" ]] || die "-m is required"

############################################
# Validate dependencies
############################################

command -v fslmaths >/dev/null 2>&1 || \
    die "fslmaths not found in PATH"

command -v fslstats >/dev/null 2>&1 || \
    die "fslstats not found in PATH"

############################################
# Determine starting orientation
############################################

declare -a files_to_process=()

if is_valid_orientation "$mask_or_orientation"; then

    input_orientation=$(echo "$mask_or_orientation" | tr '[:lower:]' '[:upper:]')

    echo
    echo "Using explicit starting orientation: ${input_orientation}"

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

    # When -m is an image, it is also reoriented.
    files_to_process+=("$mask_or_orientation")

fi

############################################
# Orientation detection only
############################################

if [[ -z "$reference_orientation" ]]; then

    if is_valid_orientation "$mask_or_orientation"; then
        echo
        echo "Starting orientation: ${input_orientation}"
    else
        echo
        echo "Orientation detection complete."
    fi

    echo
    exit 0
fi

############################################
# Determine reference orientation
############################################

if [[ -f "$reference_orientation" ]]; then

    echo
    echo "Reference orientation image detected:"
    echo "    ${reference_orientation}"

    ref_mask=$(prepare_temp_binary_mask "$reference_orientation")

    output_orientation=$(predict_orientation "$ref_mask")

    [[ -n "$output_orientation" ]] || \
        die "Failed to determine orientation from reference image: ${reference_orientation}"

    echo
    echo "Automatic reference orientation found: ${output_orientation}"

else

    output_orientation=$(echo "$reference_orientation" | tr '[:lower:]' '[:upper:]')

    is_valid_orientation "$output_orientation" || \
        die "Invalid reference orientation: ${reference_orientation}"

    echo
    echo "Using explicit reference orientation: ${output_orientation}"

fi

############################################
# Validate/create output directory
############################################

[[ -n "$output_dir" ]] || \
    die "-o output directory is required when using -r"

mkdir -p "$output_dir"

[[ -d "$output_dir" ]] || \
    die "Failed to create output directory: ${output_dir}"

############################################
# Validate transform executable
############################################

[[ -x "$transform_exec" ]] || \
    die "Transform executable missing or not executable: ${transform_exec}"

############################################
# Parse -f files
############################################

if [[ -n "$files_csv" ]]; then

    IFS=',' read -ra additional_files <<< "$files_csv"

    for f in "${additional_files[@]}"; do

        # Trim leading/trailing whitespace
        f="${f#"${f%%[![:space:]]*}"}"
        f="${f%"${f##*[![:space:]]}"}"

        [[ -z "$f" ]] && continue

        [[ -f "$f" ]] || \
            die "File does not exist: ${f}"

        files_to_process+=("$f")

    done

fi

[[ ${#files_to_process[@]} -gt 0 ]] || \
    die "No files to reorient"

############################################
# Reorient
############################################

echo
echo "===================================================="
echo "Beginning reorientation"
echo "===================================================="
echo
echo "Starting orientation : ${input_orientation}"
echo "Reference orientation: ${output_orientation}"
echo "Output directory      : ${output_dir}"

for infile in "${files_to_process[@]}"; do

    echo
    echo "Reorienting ${infile}"
    echo "    ${input_orientation} -> ${output_orientation}"

    "$transform_exec" \
        "$mcr" \
        "$infile" \
        "$input_orientation" \
        "$output_orientation" \
        "${output_dir}/"

    outfile="${output_dir}/$(basename "$infile")"

    echo "Output:"
    echo "    ${outfile}"

done

echo
echo "===================================================="
echo "Done"
echo "Output file(s) are in:"
echo "    ${output_dir}"
echo "===================================================="
echo
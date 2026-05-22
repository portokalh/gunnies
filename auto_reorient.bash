#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<EOF

Usage:
    $(basename "$0") <input_dir> <output_dir> <output_orientation_or_mask> <mask> [T2]

Arguments:
    input_dir                  Input directory (currently informational)
    output_dir                 Output directory
    output_orientation_or_mask Either:
                                 - valid 3-letter orientation (e.g. ALS, RPI, LPS)
                                 - OR a mask/image whose orientation will be inferred
    mask                       Input mask image (required)
    T2                         Input T2 image (optional)

Examples:
    $(basename "$0") ./input ./output ALS brain_mask.nii.gz T2.nii.gz

    $(basename "$0") ./input ./output reference_mask.nii.gz brain_mask.nii.gz

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
# Main
############################################

if [[ $# -lt 4 || $# -gt 5 ]]; then
    usage
    exit 1
fi

input_dir="$1"
output_dir="$2"
output_orientation_input="$3"
mask="$4"
T2="${5:-}"

############################################
# Check input directory
############################################

if [[ ! -d "${input_dir}" ]]; then
    echo "ERROR: Input directory does not exist:"
    echo "    ${input_dir}"
    exit 1
fi

############################################
# Check mask
############################################

if [[ ! -f "${mask}" ]]; then
    echo "ERROR: Mask file does not exist:"
    echo "    ${mask}"
    exit 1
fi

############################################
# Check optional T2
############################################

if [[ -n "${T2}" && ! -f "${T2}" ]]; then
    echo "ERROR: T2 file does not exist:"
    echo "    ${T2}"
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
    echo "ERROR: Failed to determine orientation of input mask:"
    echo "    ${mask}"
    exit 1
fi

echo
echo "Automatic input orientation found: ${input_orientation}"

############################################
# Determine output orientation
############################################

if [[ -f "${output_orientation_input}" ]]; then

    echo
    echo "Output orientation input appears to be an image/mask:"
    echo "    ${output_orientation_input}"

    output_orientation=$(predict_orientation "${output_orientation_input}")

    if [[ -z "${output_orientation}" ]]; then
        echo "ERROR: Failed to determine orientation from output reference mask:"
        echo "    ${output_orientation_input}"
        exit 1
    fi

    echo "Automatic output orientation found: ${output_orientation}"

else

    output_orientation="${output_orientation_input}"

    if ! is_valid_orientation "${output_orientation}"; then
        echo "ERROR: Invalid output orientation:"
        echo "    ${output_orientation}"
        echo
        echo "Expected either:"
        echo "    - valid 3-letter orientation (e.g. ALS, RPI, LPS)"
        echo "    - OR a valid image/mask file"
        exit 1
    fi

    echo
    echo "Using explicit output orientation: ${output_orientation}"

fi

############################################
# MATLAB executable path
############################################

transform_exec="/home/apps/matlab_execs_for_SAMBA/img_transform_executable/run_img_transform_exec.sh"
mcr="/home/apps/MATLAB2015b_runtime/v90"

if [[ ! -x "${transform_exec}" ]]; then
    echo "ERROR: Transform executable not found or not executable:"
    echo "    ${transform_exec}"
    exit 1
fi

############################################
# Reorient mask
############################################

echo
echo "Reorienting:"
echo "    ${mask}"
echo "FROM:"
echo "    ${input_orientation}"
echo "TO:"
echo "    ${output_orientation}"

"${transform_exec}" \
    "${mcr}" \
    "${mask}" \
    "${input_orientation}" \
    "${output_orientation}" \
    "${output_dir}/"

mask_output="${output_dir}/$(basename "${mask}")"

echo
echo "Mask output written to:"
echo "    ${mask_output}"

############################################
# Reorient optional T2
############################################

if [[ -n "${T2}" ]]; then

    echo
    echo "Reorienting:"
    echo "    ${T2}"
    echo "FROM:"
    echo "    ${input_orientation}"
    echo "TO:"
    echo "    ${output_orientation}"

    "${transform_exec}" \
        "${mcr}" \
        "${T2}" \
        "${input_orientation}" \
        "${output_orientation}" \
        "${output_dir}/"

    T2_output="${output_dir}/$(basename "${T2}")"

    echo
    echo "T2 output written to:"
    echo "    ${T2_output}"

fi

echo
echo "Done."
echo
#!/bin/bash
#SBATCH --job-name=n4_batch
#SBATCH --output=slurm-%A_%a.out
#SBATCH --error=slurm-%A_%a.out
#SBATCH --time=04:00:00
#SBATCH --mem=8G
#SBATCH --cpus-per-task=2
#SBATCH --array=0-999   # upper bound; script safely exits if index too high

set -euo pipefail

# -------- USER INPUT --------
INPUT_DIR="$1"
INPUT_DIR=$(realpath "$INPUT_DIR")

# -------- DISCOVER FILES (INSIDE JOB, NOT PRECOMPUTED) --------
mapfile -t FILES < <(find "$INPUT_DIR" -type f \( -name "*.nii" -o -name "*.nii.gz" \) | sort)

N=${#FILES[@]}

if [[ "$SLURM_ARRAY_TASK_ID" -ge "$N" ]]; then
    echo "Index $SLURM_ARRAY_TASK_ID >= $N files → exiting"
    exit 0
fi

INPUT="${FILES[$SLURM_ARRAY_TASK_ID]}"

OUT_DIR=$(dirname "$INPUT")
BASE=$(basename "$INPUT")
STEM=${BASE%.nii.gz}
STEM=${STEM%.nii}

OUT="$OUT_DIR/${STEM}_bfc.nii.gz"
BIAS="$OUT_DIR/${STEM}_biasfield.nii.gz"
MASK_TMP="$OUT_DIR/${STEM}_mask_tmp.nii.gz"

echo "===================================="
echo "Job ID      : $SLURM_JOB_ID"
echo "Array Index : $SLURM_ARRAY_TASK_ID"
echo "Processing  : $INPUT"
echo "===================================="

# -------- SUPPORT MASK --------
ThresholdImage 3 "$INPUT" "$MASK_TMP" Otsu 4
ThresholdImage 3 "$MASK_TMP" "$MASK_TMP" 2 4 1 0
ImageMath 3 "$MASK_TMP" GetLargestComponent "$MASK_TMP"
ImageMath 3 "$MASK_TMP" FillHoles "$MASK_TMP" 2

# -------- N4 --------
N4BiasFieldCorrection \
    -d 3 \
    -i "$INPUT" \
    -x "$MASK_TMP" \
    -s 1 \
    -c [200x200x100x50,1e-8] \
    -b [8] \
    -t [0.15,0.01,200] \
    -r 1 \
    -o ["$OUT","$BIAS"]

rm -f "$MASK_TMP"

echo "DONE: $OUT"
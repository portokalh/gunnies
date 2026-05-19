#!/usr/bin/env python3

import argparse
import re
import subprocess
import sys
from pathlib import Path


def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


def shell_quote(s: str) -> str:
    return "'" + s.replace("'", "'\"'\"'") + "'"


def submit_job(script_path: Path):
    result = subprocess.run(
        ["sbatch", "--parsable", str(script_path)],
        capture_output=True,
        text=True,
    )
    return result.returncode, result.stdout.strip(), result.stderr.strip()


def parse_job_id(stdout: str) -> str:
    m = re.match(r"^(\d+)", stdout.strip())
    if not m:
        raise RuntimeError(f"Could not parse job id from: {stdout}")
    return m.group(1)


def build_job_script(
    *,
    input_nii: Path,
    output_nii: Path,
    bias_nii: Path,
    mask_nii: Path | None,
    method_in: Path | None,
    method_out: Path | None,
    sbatch_dir: Path,
    n4_path: str,
    imagemath_path: str,
    dimension: int,
    shrink_factor: int,
    convergence: str,
    bspline: str,
    histogram_sharpening: str,
    mask_dilate_iters: int,
    threads: int,
    cpus: int,
    mem_gb: int,
    time_str: str,
    partition: str | None,
    overwrite: bool,
    job_name: str,
):
    log_pattern = sbatch_dir / "slurm-%j.out"

    lines = [
        "#!/bin/bash",
        f"#SBATCH --job-name={job_name}",
        f"#SBATCH --output={log_pattern}",
        f"#SBATCH --error={log_pattern}",
        f"#SBATCH --cpus-per-task={cpus}",
        f"#SBATCH --mem={mem_gb}G",
        f"#SBATCH --time={time_str}",
    ]

    if partition:
        lines.append(f"#SBATCH --partition={partition}")

    script = "\n".join(lines) + "\n\n"

    script += f"""\
set -euo pipefail

echo "===== JOB START ====="
date
hostname
echo "SLURM_JOB_ID=${{SLURM_JOB_ID:-}}"

export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS={threads}

input_nii={shell_quote(str(input_nii))}
output_nii={shell_quote(str(output_nii))}
bias_nii={shell_quote(str(bias_nii))}
overwrite_flag={"1" if overwrite else "0"}

n4_exe={shell_quote(n4_path)}
imagemath_exe={shell_quote(imagemath_path)}

"""

    if mask_nii is not None:
        script += f"mask_nii={shell_quote(str(mask_nii))}\n"
    else:
        script += 'mask_nii=""\n'

    if method_in is not None:
        script += f"method_in={shell_quote(str(method_in))}\n"
    else:
        script += 'method_in=""\n'

    if method_out is not None:
        script += f"method_out={shell_quote(str(method_out))}\n"
    else:
        script += 'method_out=""\n'

    script += f"""

if [[ ! -f "$input_nii" ]]; then
    echo "ERROR: Missing input: $input_nii"
    exit 1
fi

if [[ "$overwrite_flag" != "1" ]]; then
    if [[ -f "$output_nii" && -f "$bias_nii" ]]; then
        echo "Outputs already exist; skipping."
        exit 0
    fi
fi

cmd=(
    "$n4_exe"
    -d {dimension}
    -i "$input_nii"
)

"""

    if mask_nii is not None:
        script += f"""
if [[ ! -f "$mask_nii" ]]; then
    echo "ERROR: Missing mask: $mask_nii"
    exit 1
fi

dilated_mask="$(dirname "$mask_nii")/$(basename "$mask_nii" .nii.gz)_dilated_tmp.nii.gz"

echo
echo "Dilating mask..."
"$imagemath_exe" {dimension} "$dilated_mask" MD "$mask_nii" {mask_dilate_iters}

if [[ ! -f "$dilated_mask" ]]; then
    echo "ERROR: Failed to create dilated mask."
    exit 1
fi

cmd+=( -x "$dilated_mask" )

"""

    script += f"""
cmd+=(
    -s {shrink_factor}
    -c {shell_quote(convergence)}
    -b {shell_quote(bspline)}
    -t {shell_quote(histogram_sharpening)}
    -r 1
    -o "[""$output_nii"",""$bias_nii""]"
)

echo
echo "Running N4BiasFieldCorrection:"
printf '  %q' "${{cmd[@]}}"
echo

"${{cmd[@]}}"

if [[ ! -f "$output_nii" ]]; then
    echo "ERROR: Missing output image."
    exit 1
fi

if [[ -n "$method_in" && -f "$method_in" && -n "$method_out" ]]; then
    cp -f "$method_in" "$method_out"
fi

"""

    if mask_nii is not None:
        script += """
rm -f "$dilated_mask"
"""

    script += """
echo
echo "===== JOB END ====="
date
"""

    return script


def main():
    p = argparse.ArgumentParser(
        description="Submit Slurm N4 jobs for matching NIfTIs in ONE folder (non-recursive)."
    )

    p.add_argument("--input_dir", required=True)

    p.add_argument(
        "--input_pattern",
        required=True,
        help='Example: "*_T2.nii.gz"',
    )

    p.add_argument(
        "--mask_pattern",
        default=None,
        help='Example: "*_T2_pred_mask.nii.gz"',
    )

    p.add_argument(
        "--output_suffix",
        default="_bfc",
    )

    p.add_argument(
        "--bias_suffix",
        default="_biasfield",
    )

    p.add_argument(
        "--mask_dilate_iters",
        type=int,
        default=4,
    )

    p.add_argument(
        "--n4_path",
        default="N4BiasFieldCorrection",
    )

    p.add_argument(
        "--imagemath_path",
        default="ImageMath",
    )

    p.add_argument("--dimension", type=int, default=3)

    p.add_argument("--shrink_factor", type=int, default=1)

    p.add_argument(
        "--convergence",
        default="[200x200x100x50,1e-8]",
    )

    p.add_argument(
        "--bspline",
        default="[8]",
    )

    p.add_argument(
        "--histogram_sharpening",
        default="[0.15,0.01,200]",
    )

    p.add_argument("--threads", type=int, default=4)
    p.add_argument("--cpus", type=int, default=4)
    p.add_argument("--mem_gb", type=int, default=16)
    p.add_argument("--time", default="04:00:00")
    p.add_argument("--partition", default=None)

    p.add_argument("--overwrite", action="store_true")
    p.add_argument("--dry_run", action="store_true")

    args = p.parse_args()

    input_dir = Path(args.input_dir).expanduser().resolve()

    if not input_dir.exists():
        eprint(f"ERROR: input_dir does not exist: {input_dir}")
        return 1

    sbatch_dir = input_dir / "sbatch"
    sbatch_dir.mkdir(parents=True, exist_ok=True)

    # NON-RECURSIVE
    nifti_paths = sorted(input_dir.glob(args.input_pattern))

    if not nifti_paths:
        eprint("ERROR: No matching files found.")
        return 1

    print(f"[INFO] input_dir : {input_dir}")
    print(f"[INFO] matches   : {len(nifti_paths)}")

    for input_nii in nifti_paths:

        if not input_nii.is_file():
            continue

        name = input_nii.name

        if not name.endswith(".nii.gz"):
            continue

        stem = name[:-7]

        output_nii = input_nii.with_name(
            f"{stem}{args.output_suffix}.nii.gz"
        )

        bias_nii = input_nii.with_name(
            f"{stem}{args.bias_suffix}.nii.gz"
        )

        method_in = input_nii.with_name(f"{stem}.method")
        method_out = output_nii.with_suffix("").with_suffix(".method")

        mask_nii = None

        if args.mask_pattern is not None:

            if "*" not in args.input_pattern:
                raise RuntimeError(
                    "input_pattern must contain '*' when using mask_pattern"
                )

            token = args.input_pattern.replace("*", "")

            if token not in name:
                raise RuntimeError(
                    f"Could not map mask pattern for {name}"
                )

            prefix = name.replace(token, "")

            mask_name = args.mask_pattern.replace("*", prefix)

            mask_nii = input_dir / mask_name

            if not mask_nii.exists():
                eprint(f"[SKIP] Missing mask: {mask_nii}")
                continue

        job_name = f"n4_{stem}"

        tmp_script = sbatch_dir / f"TMP_{job_name}.sbatch"

        script_text = build_job_script(
            input_nii=input_nii,
            output_nii=output_nii,
            bias_nii=bias_nii,
            mask_nii=mask_nii,
            method_in=method_in if method_in.exists() else None,
            method_out=method_out,
            sbatch_dir=sbatch_dir,
            n4_path=args.n4_path,
            imagemath_path=args.imagemath_path,
            dimension=args.dimension,
            shrink_factor=args.shrink_factor,
            convergence=args.convergence,
            bspline=args.bspline,
            histogram_sharpening=args.histogram_sharpening,
            mask_dilate_iters=args.mask_dilate_iters,
            threads=args.threads,
            cpus=args.cpus,
            mem_gb=args.mem_gb,
            time_str=args.time,
            partition=args.partition,
            overwrite=args.overwrite,
            job_name=job_name,
        )

        tmp_script.write_text(script_text)

        print(f"[PREPARED] {input_nii.name}")

        if args.dry_run:
            continue

        rc, stdout, stderr = submit_job(tmp_script)

        if rc != 0:
            eprint(f"[SUBMIT FAIL] {input_nii.name}")

            if stdout:
                eprint(stdout)

            if stderr:
                eprint(stderr)

            continue

        job_id = parse_job_id(stdout)

        final_script = sbatch_dir / f"{job_id}_{job_name}.sbatch"

        tmp_script.rename(final_script)

        print(f"[SUBMITTED] {input_nii.name}")
        print(f"  job_id : {job_id}")
        print(f"  script : {final_script}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
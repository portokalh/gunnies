#!/usr/bin/env python3
"""
vfa_t1map_2fa.py

Compute a T1 map from two spoiled GRE (SPGR/FLASH) volumes acquired with two flip angles
using the two-point variable flip angle (VFA) method:

S(a) = K * (1 - E1) * sin(a) / (1 - E1 * cos(a)),  E1 = exp(-TR/T1)

Two-point solution (voxelwise):
E1 = [S2/sin(a2) - S1/sin(a1)] / [S2/tan(a2) - S1/tan(a1)]
T1 = -TR / ln(E1)

Inputs:
- Two NIfTI images (same shape, already aligned)
- TR and flip angles from CLI or inferred from adjacent .method files

Method file parsing:
- Attempts to parse Bruker-ish '##$KEY=VALUE' entries.
- Searches multiple candidate keys for TR and flip angle.

Examples:
  # Fully manual:
  python vfa_t1map_2fa.py --img1 fa5.nii.gz --img2 fa15.nii.gz --fa1 5 --fa2 15 --tr 0.015 --out t1.nii.gz

  # Parse from adjacent method files (fa5.method, fa15.method):
  python vfa_t1map_2fa.py --img1 fa5.nii.gz --img2 fa15.nii.gz --out t1.nii.gz

  # Provide method files explicitly:
  python vfa_t1map_2fa.py --img1 fa5.nii.gz --img2 fa15.nii.gz --method1 /path/fa5.method --method2 /path/fa15.method --out t1.nii.gz
"""

import argparse
import math
import os
import re
import sys
from typing import Dict, Optional, Tuple, List

import numpy as np
import nibabel as nib


# -------------------------
# Method file parsing utils
# -------------------------

def _strip_quotes(s: str) -> str:
    s = s.strip()
    if len(s) >= 2 and ((s[0] == '"' and s[-1] == '"') or (s[0] == "'" and s[-1] == "'")):
        return s[1:-1]
    return s


def parse_bruker_method(method_path: str) -> Dict[str, str]:
    """
    Parse a Bruker-style .method file into a dict of key->raw_value_string.
    Handles values that span multiple lines (common with arrays/lists).

    We treat entries of the form:
      ##$KEY=VALUE
    and gather subsequent lines until the next "##$" entry or EOF.
    """
    if not os.path.isfile(method_path):
        raise FileNotFoundError(f"Method file not found: {method_path}")

    with open(method_path, "r", encoding="utf-8", errors="replace") as f:
        lines = f.readlines()

    data: Dict[str, str] = {}
    key = None
    buf: List[str] = []

    entry_re = re.compile(r"^\s*##\$(?P<key>[A-Za-z0-9_]+)\s*=\s*(?P<val>.*)\s*$")

    def flush():
        nonlocal key, buf
        if key is not None:
            data[key] = "\n".join(buf).strip()
        key = None
        buf = []

    for line in lines:
        m = entry_re.match(line)
        if m:
            flush()
            key = m.group("key").strip()
            buf = [m.group("val").strip()]
        else:
            # Continue current value if we are inside an entry
            if key is not None:
                buf.append(line.rstrip("\n"))
            # else ignore non-entry lines

    flush()
    return data


def _extract_first_number(raw: str) -> Optional[float]:
    """
    Extract the first float-like token from a raw value string.
    Handles things like:
      "15"
      "( 1 ) 15"
      "( 2 ) 5 15"
      "15.0"
      "<15>"
    Returns None if nothing found.
    """
    if raw is None:
        return None
    s = raw.strip()
    s = _strip_quotes(s)

    # Remove angle brackets if present
    s = s.replace("<", " ").replace(">", " ")

    # Find first number (int/float/scientific)
    m = re.search(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", s)
    if not m:
        return None
    try:
        return float(m.group(0))
    except Exception:
        return None


def _extract_all_numbers(raw: str) -> List[float]:
    if raw is None:
        return []
    s = _strip_quotes(raw.strip()).replace("<", " ").replace(">", " ")
    nums = re.findall(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", s)
    out = []
    for n in nums:
        try:
            out.append(float(n))
        except Exception:
            pass
    return out


def infer_tr_and_fa_from_method_dict(d: Dict[str, str]) -> Tuple[Optional[float], Optional[float], str]:
    """
    Attempt to infer TR (seconds) and flip angle (degrees) from a parsed method dict.

    Returns (tr_seconds, fa_degrees, details_string)

    Notes:
    - Many Bruker methods store TR in ms (often PVM_RepetitionTime).
    - Flip angle may be in degrees (PVM_FlipAngle) or other keys depending on sequence.
    """
    # Candidate keys (add more if your site uses different names)
    tr_keys = [
        "PVM_RepetitionTime",     # common; usually ms
        "RepetitionTime",         # sometimes
        "TR",                     # rare in method
        "PVM_TR",                 # sometimes
    ]

    fa_keys = [
        "PVM_FlipAngle",          # common (degrees)
        "FlipAngle",              # sometimes
        "ExcPulseAngle",          # sometimes
        "PVM_ExcFlipAngle",       # sometimes
        "PVM_ExcPulseAngle",      # sometimes
    ]

    tr_raw = None
    tr_key_used = None
    for k in tr_keys:
        if k in d:
            tr_raw = d[k]
            tr_key_used = k
            break

    fa_raw = None
    fa_key_used = None
    for k in fa_keys:
        if k in d:
            fa_raw = d[k]
            fa_key_used = k
            break

    tr_val = _extract_first_number(tr_raw) if tr_raw is not None else None
    fa_val = _extract_first_number(fa_raw) if fa_raw is not None else None

    # Heuristic: TR in method is very often ms; convert to seconds.
    # If TR is suspiciously small (<0.5), it might already be seconds; but typical Bruker ms is 5-100 ms.
    tr_seconds = None
    tr_note = ""
    if tr_val is not None:
        # If value looks like milliseconds (e.g., 5..200), convert to seconds.
        # If it looks like seconds (e.g., 0.005..0.2), keep as seconds.
        if tr_val > 0.5:  # likely ms
            tr_seconds = tr_val / 1000.0
            tr_note = f"TR inferred from {tr_key_used}={tr_val} (assumed ms -> {tr_seconds:.6g} s)"
        else:
            tr_seconds = tr_val
            tr_note = f"TR inferred from {tr_key_used}={tr_val} (assumed s)"
    else:
        tr_note = "TR not found in method"

    fa_degrees = None
    fa_note = ""
    if fa_val is not None:
        fa_degrees = fa_val
        fa_note = f"Flip angle inferred from {fa_key_used}={fa_val} (degrees assumed)"
    else:
        fa_note = "Flip angle not found in method"

    details = f"{tr_note}; {fa_note}"
    return tr_seconds, fa_degrees, details


def default_adjacent_method_path(nifti_path: str) -> str:
    """
    Given /path/foo.nii.gz -> /path/foo.method
    Given /path/foo.nii -> /path/foo.method
    """
    base = os.path.basename(nifti_path)
    d = os.path.dirname(os.path.abspath(nifti_path))

    if base.endswith(".nii.gz"):
        stem = base[:-7]
    elif base.endswith(".nii"):
        stem = base[:-4]
    else:
        # unknown extension; just strip last extension
        stem = os.path.splitext(base)[0]

    return os.path.join(d, f"{stem}.method")


# -------------------------
# Core VFA computation
# -------------------------

def vfa_t1_two_point(
    S1: np.ndarray,
    S2: np.ndarray,
    fa1_deg: float,
    fa2_deg: float,
    tr_s: float,
    mask: Optional[np.ndarray] = None,
    e1_min: float = 1e-6,
    e1_max: float = 0.999999,
) -> np.ndarray:
    """
    Compute voxelwise T1 map (seconds).
    """
    if tr_s <= 0:
        raise ValueError(f"TR must be > 0 seconds; got {tr_s}")

    a1 = np.deg2rad(fa1_deg)
    a2 = np.deg2rad(fa2_deg)

    # Avoid degenerate angles
    if not (0 < fa1_deg < 180) or not (0 < fa2_deg < 180):
        raise ValueError(f"Flip angles must be in (0,180) degrees; got {fa1_deg}, {fa2_deg}")
    if abs(np.sin(a1)) < 1e-12 or abs(np.sin(a2)) < 1e-12:
        raise ValueError("Flip angles too close to 0 or 180 degrees; sin(angle) ~ 0.")
    if abs(np.tan(a1)) < 1e-12 or abs(np.tan(a2)) < 1e-12:
        raise ValueError("Flip angles too close to 0 or 180 degrees; tan(angle) ~ 0.")

    S1 = S1.astype(np.float64, copy=False)
    S2 = S2.astype(np.float64, copy=False)

    # Core formula
    y1 = S1 / np.sin(a1)
    y2 = S2 / np.sin(a2)
    x1 = S1 / np.tan(a1)
    x2 = S2 / np.tan(a2)

    denom = (x2 - x1)
    numer = (y2 - y1)

    # Compute E1 safely
    E1 = np.full(S1.shape, np.nan, dtype=np.float64)
    good = np.isfinite(numer) & np.isfinite(denom) & (np.abs(denom) > 0)

    # Also require positive-ish signals to reduce noise-only nonsense
    good &= (S1 > 0) & (S2 > 0)

    if mask is not None:
        good &= (mask != 0)

    E1[good] = numer[good] / denom[good]

    # Clamp E1 into (0,1)
    E1 = np.clip(E1, e1_min, e1_max)

    # T1 = -TR / ln(E1)
    T1 = -tr_s / np.log(E1)

    # Any voxels that were never "good" remain meaningless; set to 0
    # (common in output maps; you can change to NaN if you prefer)
    T1[~good] = 0.0

    return T1


def build_default_mask(S1: np.ndarray, S2: np.ndarray, frac: float = 0.05) -> np.ndarray:
    """
    Simple intensity-based mask: keep voxels above frac * 95th percentile of combined signal.
    (Crude but useful when no external mask is provided.)
    """
    comb = np.maximum(S1, S2)
    comb = comb[np.isfinite(comb)]
    if comb.size == 0:
        return np.zeros(S1.shape, dtype=np.uint8)

    p = np.percentile(comb, 95)
    thr = frac * p
    return (np.maximum(S1, S2) > thr).astype(np.uint8)


# -------------------------
# I/O and CLI
# -------------------------

def load_nifti(path: str) -> Tuple[np.ndarray, nib.Nifti1Image]:
    img = nib.load(path)
    data = img.get_fdata(dtype=np.float32)  # float32 enough for input
    return data, img


def main():
    ap = argparse.ArgumentParser(
        description="Compute a 2-point VFA T1 map from two flip-angle NIfTI volumes, with optional .method parsing."
    )
    ap.add_argument("--img1", required=True, help="NIfTI for flip angle 1")
    ap.add_argument("--img2", required=True, help="NIfTI for flip angle 2")
    ap.add_argument("--out", required=True, help="Output T1 map NIfTI (.nii or .nii.gz)")

    ap.add_argument("--fa1", type=float, default=None, help="Flip angle 1 in degrees (optional if parsed from method)")
    ap.add_argument("--fa2", type=float, default=None, help="Flip angle 2 in degrees (optional if parsed from method)")
    ap.add_argument("--tr", type=float, default=None, help="TR value (optional if parsed from method)")
    ap.add_argument(
        "--tr-units",
        choices=["s", "ms"],
        default="s",
        help="Units for --tr if provided manually. Default: s",
    )

    ap.add_argument("--method1", default=None, help="Explicit .method file for img1 (optional)")
    ap.add_argument("--method2", default=None, help="Explicit .method file for img2 (optional)")
    ap.add_argument(
        "--require-same-tr",
        action="store_true",
        help="If TR is parsed from both method files, require they match (within tolerance).",
    )

    ap.add_argument("--mask", default=None, help="Optional binary mask NIfTI")
    ap.add_argument(
        "--auto-mask",
        action="store_true",
        help="If no --mask is provided, build a simple intensity mask automatically.",
    )
    ap.add_argument(
        "--auto-mask-frac",
        type=float,
        default=0.05,
        help="Auto-mask threshold as fraction of 95th percentile (default 0.05).",
    )

    ap.add_argument("--e1-min", type=float, default=1e-6, help="Minimum clamp for E1 (default 1e-6)")
    ap.add_argument("--e1-max", type=float, default=0.999999, help="Maximum clamp for E1 (default 0.999999)")

    args = ap.parse_args()

    img1_path = args.img1
    img2_path = args.img2

    # Load images
    S1, img1 = load_nifti(img1_path)
    S2, img2 = load_nifti(img2_path)

    if S1.shape != S2.shape:
        raise SystemExit(f"ERROR: Shape mismatch: img1 {S1.shape} vs img2 {S2.shape}")

    # Load / build mask
    mask = None
    if args.mask is not None:
        mdata, _mimg = load_nifti(args.mask)
        if mdata.shape != S1.shape:
            raise SystemExit(f"ERROR: Mask shape mismatch: mask {mdata.shape} vs images {S1.shape}")
        mask = (mdata != 0).astype(np.uint8)
    elif args.auto_mask:
        mask = build_default_mask(S1, S2, frac=args.auto_mask_frac)

    # Resolve TR and flip angles: manual takes precedence; otherwise parse from method
    fa1 = args.fa1
    fa2 = args.fa2
    tr_s = None

    # Manual TR if provided
    if args.tr is not None:
        tr_s = args.tr / 1000.0 if args.tr_units == "ms" else args.tr

    # If any of (fa1, fa2, tr_s) missing, try method parsing
    need_fa1 = (fa1 is None)
    need_fa2 = (fa2 is None)
    need_tr = (tr_s is None)

    method1_path = args.method1 or default_adjacent_method_path(img1_path)
    method2_path = args.method2 or default_adjacent_method_path(img2_path)

    method1_exists = os.path.isfile(method1_path)
    method2_exists = os.path.isfile(method2_path)

    parsed_tr1 = parsed_fa1 = None
    parsed_tr2 = parsed_fa2 = None

    details = []

    if need_fa1 or need_tr:
        if method1_exists:
            d1 = parse_bruker_method(method1_path)
            parsed_tr1, parsed_fa1, det1 = infer_tr_and_fa_from_method_dict(d1)
            details.append(f"[method1] {method1_path}: {det1}")
        else:
            details.append(f"[method1] not found at expected path: {method1_path}")

    if need_fa2 or (need_tr and args.require_same_tr):
        if method2_exists:
            d2 = parse_bruker_method(method2_path)
            parsed_tr2, parsed_fa2, det2 = infer_tr_and_fa_from_method_dict(d2)
            details.append(f"[method2] {method2_path}: {det2}")
        else:
            details.append(f"[method2] not found at expected path: {method2_path}")

    # Fill missing FA/TR from parsed values
    if fa1 is None:
        fa1 = parsed_fa1
    if fa2 is None:
        fa2 = parsed_fa2
    if tr_s is None:
        # Prefer TR from method1, else method2
        tr_s = parsed_tr1 if parsed_tr1 is not None else parsed_tr2

    # Validate we have required parameters
    missing = []
    if fa1 is None:
        missing.append("fa1")
    if fa2 is None:
        missing.append("fa2")
    if tr_s is None:
        missing.append("tr")

    if missing:
        msg = [
            "ERROR: Missing required parameter(s): " + ", ".join(missing),
            "Provide them via CLI (--fa1/--fa2/--tr) OR ensure adjacent .method files exist and contain them.",
            "",
            "Method parsing diagnostics:",
            *details,
            "",
            "Expected default adjacent method paths:",
            f"  img1 -> {default_adjacent_method_path(img1_path)}",
            f"  img2 -> {default_adjacent_method_path(img2_path)}",
            "",
            "You can also pass explicit method paths with --method1 and --method2.",
        ]
        raise SystemExit("\n".join(msg))

    # Optionally require TR consistency if both were parsed
    if args.require_same_tr and (parsed_tr1 is not None) and (parsed_tr2 is not None):
        # tolerance: relative 1e-6 or absolute 1e-9 seconds
        if not np.isclose(parsed_tr1, parsed_tr2, rtol=1e-6, atol=1e-9):
            raise SystemExit(
                "ERROR: TR mismatch between method files:\n"
                f"  method1 TR={parsed_tr1} s\n"
                f"  method2 TR={parsed_tr2} s\n"
                "If this is expected, omit --require-same-tr, or provide --tr explicitly."
            )

    # Compute T1
    T1 = vfa_t1_two_point(
        S1=S1,
        S2=S2,
        fa1_deg=float(fa1),
        fa2_deg=float(fa2),
        tr_s=float(tr_s),
        mask=mask,
        e1_min=args.e1_min,
        e1_max=args.e1_max,
    )

    # Save output using img1 affine/header as reference
    out_img = nib.Nifti1Image(T1.astype(np.float32), affine=img1.affine, header=img1.header)
    out_img.header.set_data_dtype(np.float32)
    nib.save(out_img, args.out)

    # Print summary
    print("=== VFA T1 mapping (2-point) ===")
    print(f"img1: {img1_path}")
    print(f"img2: {img2_path}")
    print(f"out : {args.out}")
    print(f"FA1 : {fa1} deg")
    print(f"FA2 : {fa2} deg")
    print(f"TR  : {tr_s:.6g} s")
    if args.mask:
        print(f"mask: {args.mask}")
    elif args.auto_mask:
        print(f"mask: auto (frac={args.auto_mask_frac})")
    else:
        print("mask: none")
    if details:
        print("--- method parsing ---")
        for d in details:
            print(d)
    print("Done.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
vfa_t1map_2fa.py

2-point VFA (DESPOT1-style) T1 mapping from two spoiled GRE (SPGR/FLASH) images.

Usage:
  # positional:
  python vfa_t1map_2fa.py img1.nii.gz img2.nii.gz out_t1.nii.gz

  # named:
  python vfa_t1map_2fa.py --img1 img1.nii.gz --img2 img2.nii.gz --out out_t1.nii.gz

  # override/force:
  python vfa_t1map_2fa.py img1.nii.gz img2.nii.gz out_t1.nii.gz --fa1 5 --fa2 15 --tr 0.015

Flip angles/TR can be provided manually or inferred from adjacent .method files:
  foo.nii.gz -> foo.method
or explicitly via --method1/--method2.

Bruker .method parsing:
- TR commonly stored as PVM_RepetitionTime (usually ms)
- Flip angle may be stored as PVM_FlipAngle or embedded in ExcPulse1 tuple:
    ##$ExcPulse1=(1, 6000, 15, Yes, ...)
  where the third element (index 2) is the flip angle in degrees.

Output:
- T1 map (seconds) saved as float32 NIfTI using img1 affine/header.
"""

import argparse
import os
import re
from typing import Dict, Optional, Tuple, List

import numpy as np
import nibabel as nib


# -------------------------
# Method file parsing
# -------------------------

def _strip_quotes(s: str) -> str:
    s = s.strip()
    if len(s) >= 2 and ((s[0] == '"' and s[-1] == '"') or (s[0] == "'" and s[-1] == "'")):
        return s[1:-1]
    return s


def parse_bruker_method(method_path: str) -> Dict[str, str]:
    """Parse Bruker-style .method entries of the form ##$KEY=VALUE (including multiline values)."""
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
            if key is not None:
                buf.append(line.rstrip("\n"))

    flush()
    return data


def _extract_first_number(raw: Optional[str]) -> Optional[float]:
    """Extract the first float-like token from a raw method value string."""
    if raw is None:
        return None
    s = _strip_quotes(raw.strip()).replace("<", " ").replace(">", " ")
    m = re.search(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", s)
    if not m:
        return None
    try:
        return float(m.group(0))
    except Exception:
        return None


def _parse_excpulse_tuple_flip_angle(raw: Optional[str]) -> Optional[float]:
    """
    Parse flip angle from Bruker ExcPulse tuple like:
      (1, 6000, 15, Yes, 4, ...)
    We interpret the 3rd element (index 2) as flip angle in degrees
    (per user report / typical sequence convention).
    """
    if raw is None:
        return None

    s = raw.strip()

    # Some files store as "(...)" possibly across lines; keep only first line unless closing paren found
    # We'll just flatten whitespace/newlines then try to extract tuple contents.
    s = " ".join(s.split())

    # Find the first parenthesized group
    m = re.search(r"\((.*)\)", s)
    if not m:
        return None

    inside = m.group(1).strip()
    parts = [p.strip() for p in inside.split(",")]

    if len(parts) < 3:
        return None

    # Third element
    fa_str = parts[2]
    fa_val = _extract_first_number(fa_str)
    if fa_val is None:
        return None

    # sanity
    if 0 < fa_val < 180:
        return fa_val
    return None


def default_adjacent_method_path(nifti_path: str) -> str:
    base = os.path.basename(nifti_path)
    d = os.path.dirname(os.path.abspath(nifti_path))
    if base.endswith(".nii.gz"):
        stem = base[:-7]
    elif base.endswith(".nii"):
        stem = base[:-4]
    else:
        stem = os.path.splitext(base)[0]
    return os.path.join(d, f"{stem}.method")


def infer_tr_seconds(method_dict: Dict[str, str]) -> Tuple[Optional[float], str]:
    tr_keys = ["PVM_RepetitionTime", "RepetitionTime", "PVM_TR", "TR"]
    used = None
    raw = None
    for k in tr_keys:
        if k in method_dict:
            raw = method_dict[k]
            used = k
            break

    tr_val = _extract_first_number(raw)
    if tr_val is None:
        return None, "TR not found in method"

    # Heuristic: Bruker commonly stores ms
    if tr_val > 0.5:
        tr_s = tr_val / 1000.0
        return tr_s, f"TR inferred from {used}={tr_val} (assumed ms -> {tr_s:.6g} s)"
    else:
        return tr_val, f"TR inferred from {used}={tr_val} (assumed s)"


def infer_fa_degrees(method_dict: Dict[str, str]) -> Tuple[Optional[float], str]:
    """
    Infer flip angle in degrees from:
      - explicit keys (PVM_FlipAngle, etc.)
      - ExcPulse tuple keys (ExcPulse1 / PVM_ExcPulse1 / etc.)
    """
    # Direct scalar keys first
    scalar_keys = [
        "PVM_FlipAngle",
        "FlipAngle",
        "PVM_ExcPulseAngle",
        "PVM_ExcPulAngle",
        "PVM_ExcFlipAngle",
        "PVM_ExFlipAngle",
    ]
    for k in scalar_keys:
        if k in method_dict:
            v = _extract_first_number(method_dict[k])
            if v is not None and 0 < v < 180:
                return v, f"Flip angle inferred from {k}={v} (degrees assumed)"

    # ExcPulse tuple keys (your case)
    tuple_keys = [
        "ExcPulse1",
        "ExcPulse2",
        "ExcPulse",
        "PVM_ExcPulse1",
        "PVM_ExcPulse2",
        "PVM_ExcPulse",
    ]
    for k in tuple_keys:
        if k in method_dict:
            v = _parse_excpulse_tuple_flip_angle(method_dict[k])
            if v is not None:
                return v, f"Flip angle inferred from {k} tuple (3rd field) = {v} deg"

    return None, "Flip angle not found in method (no scalar key and no parsable ExcPulse tuple)"


def infer_tr_and_fa_from_method(method_path: str) -> Tuple[Optional[float], Optional[float], str]:
    d = parse_bruker_method(method_path)
    tr_s, tr_note = infer_tr_seconds(d)
    fa_deg, fa_note = infer_fa_degrees(d)
    return tr_s, fa_deg, f"{tr_note}; {fa_note}"


# -------------------------
# VFA core
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
    if tr_s <= 0:
        raise ValueError(f"TR must be > 0 seconds; got {tr_s}")
    if not (0 < fa1_deg < 180) or not (0 < fa2_deg < 180):
        raise ValueError(f"Flip angles must be in (0,180) degrees; got {fa1_deg}, {fa2_deg}")

    a1 = np.deg2rad(fa1_deg)
    a2 = np.deg2rad(fa2_deg)

    S1 = S1.astype(np.float64, copy=False)
    S2 = S2.astype(np.float64, copy=False)

    y1 = S1 / np.sin(a1)
    y2 = S2 / np.sin(a2)
    x1 = S1 / np.tan(a1)
    x2 = S2 / np.tan(a2)

    denom = x2 - x1
    numer = y2 - y1

    good = np.isfinite(numer) & np.isfinite(denom) & (np.abs(denom) > 0)
    good &= (S1 > 0) & (S2 > 0)
    if mask is not None:
        good &= (mask != 0)

    E1 = np.full(S1.shape, np.nan, dtype=np.float64)
    E1[good] = numer[good] / denom[good]
    E1 = np.clip(E1, e1_min, e1_max)

    T1 = -tr_s / np.log(E1)
    T1[~good] = 0.0
    return T1


def build_default_mask(S1: np.ndarray, S2: np.ndarray, frac: float = 0.05) -> np.ndarray:
    comb = np.maximum(S1, S2)
    comb = comb[np.isfinite(comb)]
    if comb.size == 0:
        return np.zeros(S1.shape, dtype=np.uint8)
    p = np.percentile(comb, 95)
    thr = frac * p
    return (np.maximum(S1, S2) > thr).astype(np.uint8)


def load_nifti(path: str) -> Tuple[np.ndarray, nib.Nifti1Image]:
    img = nib.load(path)
    data = img.get_fdata(dtype=np.float32)
    return data, img


# -------------------------
# CLI
# -------------------------

def parse_args():
    ap = argparse.ArgumentParser(description="Compute 2-point VFA T1 map from two NIfTI volumes with optional .method parsing.")
    ap.add_argument("positional", nargs="*", help="Optionally: img1 img2 out")
    ap.add_argument("--img1", default=None)
    ap.add_argument("--img2", default=None)
    ap.add_argument("--out", default=None)

    ap.add_argument("--fa1", type=float, default=None, help="Flip angle 1 in degrees (optional if parsed)")
    ap.add_argument("--fa2", type=float, default=None, help="Flip angle 2 in degrees (optional if parsed)")
    ap.add_argument("--tr", type=float, default=None, help="TR value (optional if parsed)")
    ap.add_argument("--tr-units", choices=["s", "ms"], default="s", help="Units for --tr if provided manually")

    ap.add_argument("--method1", default=None, help="Explicit .method file for img1 (optional)")
    ap.add_argument("--method2", default=None, help="Explicit .method file for img2 (optional)")

    ap.add_argument("--require-same-tr", action="store_true")

    ap.add_argument("--mask", default=None)
    ap.add_argument("--auto-mask", action="store_true")
    ap.add_argument("--auto-mask-frac", type=float, default=0.05)

    ap.add_argument("--e1-min", type=float, default=1e-6)
    ap.add_argument("--e1-max", type=float, default=0.999999)

    args = ap.parse_args()

    if len(args.positional) not in (0, 3):
        ap.error("If using positional args, provide exactly 3: img1 img2 out")

    if len(args.positional) == 3:
        p1, p2, pout = args.positional
        args.img1 = args.img1 or p1
        args.img2 = args.img2 or p2
        args.out = args.out or pout

    if not args.img1 or not args.img2 or not args.out:
        ap.error("Missing required inputs. Provide --img1 --img2 --out OR positional: img1 img2 out")

    return args


def main():
    args = parse_args()

    S1, img1 = load_nifti(args.img1)
    S2, img2 = load_nifti(args.img2)

    if S1.shape != S2.shape:
        raise SystemExit(f"ERROR: Shape mismatch: img1 {S1.shape} vs img2 {S2.shape}")

    mask = None
    if args.mask:
        m, _ = load_nifti(args.mask)
        if m.shape != S1.shape:
            raise SystemExit(f"ERROR: Mask shape mismatch: mask {m.shape} vs images {S1.shape}")
        mask = (m != 0).astype(np.uint8)
    elif args.auto_mask:
        mask = build_default_mask(S1, S2, frac=args.auto_mask_frac)

    fa1 = args.fa1
    fa2 = args.fa2
    tr_s = None

    if args.tr is not None:
        tr_s = args.tr / 1000.0 if args.tr_units == "ms" else args.tr

    need_fa1 = (fa1 is None)
    need_fa2 = (fa2 is None)
    need_tr = (tr_s is None)

    method1_path = args.method1 or default_adjacent_method_path(args.img1)
    method2_path = args.method2 or default_adjacent_method_path(args.img2)

    details = []
    parsed_tr1 = parsed_fa1 = None
    parsed_tr2 = parsed_fa2 = None

    if need_fa1 or need_tr:
        if os.path.isfile(method1_path):
            parsed_tr1, parsed_fa1, det = infer_tr_and_fa_from_method(method1_path)
            details.append(f"[method1] {method1_path}: {det}")
        else:
            details.append(f"[method1] not found: {method1_path}")

    if need_fa2 or (need_tr and args.require_same_tr):
        if os.path.isfile(method2_path):
            parsed_tr2, parsed_fa2, det = infer_tr_and_fa_from_method(method2_path)
            details.append(f"[method2] {method2_path}: {det}")
        else:
            details.append(f"[method2] not found: {method2_path}")

    if fa1 is None:
        fa1 = parsed_fa1
    if fa2 is None:
        fa2 = parsed_fa2
    if tr_s is None:
        tr_s = parsed_tr1 if parsed_tr1 is not None else parsed_tr2

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
            "Provide via CLI (--fa1/--fa2/--tr) OR ensure method files exist and contain them.",
            "",
            "Method parsing diagnostics:",
            *details,
            "",
            "Expected default adjacent method paths:",
            f"  img1 -> {default_adjacent_method_path(args.img1)}",
            f"  img2 -> {default_adjacent_method_path(args.img2)}",
            "",
            "You can also pass explicit method paths with --method1 and --method2.",
        ]
        raise SystemExit("\n".join(msg))

    if args.require_same_tr and (parsed_tr1 is not None) and (parsed_tr2 is not None):
        if not np.isclose(parsed_tr1, parsed_tr2, rtol=1e-6, atol=1e-9):
            raise SystemExit(
                "ERROR: TR mismatch between method files:\n"
                f"  method1 TR={parsed_tr1} s\n"
                f"  method2 TR={parsed_tr2} s\n"
                "If expected, omit --require-same-tr or provide --tr explicitly."
            )

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

    out_img = nib.Nifti1Image(T1.astype(np.float32), affine=img1.affine, header=img1.header)
    out_img.header.set_data_dtype(np.float32)
    nib.save(out_img, args.out)

    print("=== VFA T1 mapping (2-point) ===")
    print(f"img1: {args.img1}")
    print(f"img2: {args.img2}")
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

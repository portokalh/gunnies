#!/usr/bin/env python3
"""
vfa_t1map_multi.py

Compute T1 map from 2+ spoiled GRE (FLASH/SPGR) volumes acquired at different flip angles
using variable flip angle (VFA) linear regression:

S(a) = K * (1 - E1) * sin(a) / (1 - E1*cos(a))
Let:
  x = S / tan(a)
  y = S / sin(a)
Then:
  y = E1 * x + K*(1 - E1)

For >=2 flip angles, fit slope E1 via (weighted) least squares.
For exactly 2 flip angles, this reduces to the standard 2-point formula.

Inputs:
  - N NIfTI files (--imgs img1 img2 [img3 ...])
  - output path (--out)
  - flip angles/TR either given manually (--fas, --tr) OR inferred from adjacent .method files
    (same basename as nifti, .method extension), or explicit --methods.

Bruker .method parsing:
  - TR from PVM_RepetitionTime etc. (ms->s heuristic)
  - Flip angle from scalar keys or from ExcPulse1 tuple where 3rd element is FA:
      ##$ExcPulse1=(1, 6000, 15, Yes, ...)

Notes:
  - Assumes RF spoiling + adequate gradient spoiling (true SPGR/FLASH spoiled regime)
  - If B1 varies spatially, VFA T1 can be biased without B1 correction.
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
    Parse flip angle from tuple like:
      (1, 6000, 15, Yes, 4, ...)
    We interpret the 3rd element as FA in degrees.
    """
    if raw is None:
        return None
    s = " ".join(raw.strip().split())
    m = re.search(r"\((.*)\)", s)
    if not m:
        return None
    inside = m.group(1).strip()
    parts = [p.strip() for p in inside.split(",")]
    if len(parts) < 3:
        return None
    fa_val = _extract_first_number(parts[2])
    if fa_val is None:
        return None
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


def infer_tr_seconds(d: Dict[str, str]) -> Tuple[Optional[float], str]:
    tr_keys = ["PVM_RepetitionTime", "RepetitionTime", "PVM_TR", "TR"]
    used = None
    raw = None
    for k in tr_keys:
        if k in d:
            raw = d[k]
            used = k
            break
    tr_val = _extract_first_number(raw)
    if tr_val is None:
        return None, "TR not found"
    if tr_val > 0.5:
        tr_s = tr_val / 1000.0
        return tr_s, f"TR from {used}={tr_val} (ms->s => {tr_s:.6g}s)"
    return tr_val, f"TR from {used}={tr_val} (assumed s)"


def infer_fa_degrees(d: Dict[str, str]) -> Tuple[Optional[float], str]:
    scalar_keys = [
        "PVM_FlipAngle", "FlipAngle",
        "PVM_ExcPulseAngle", "PVM_ExcPulAngle",
        "PVM_ExcFlipAngle", "PVM_ExFlipAngle",
    ]
    for k in scalar_keys:
        if k in d:
            v = _extract_first_number(d[k])
            if v is not None and 0 < v < 180:
                return v, f"FA from {k}={v}"

    tuple_keys = ["ExcPulse1", "ExcPulse2", "ExcPulse", "PVM_ExcPulse1", "PVM_ExcPulse2", "PVM_ExcPulse"]
    for k in tuple_keys:
        if k in d:
            v = _parse_excpulse_tuple_flip_angle(d[k])
            if v is not None:
                return v, f"FA from {k} tuple third field = {v}"

    return None, "FA not found"


def infer_tr_fa_from_method(method_path: str) -> Tuple[Optional[float], Optional[float], str]:
    d = parse_bruker_method(method_path)
    tr_s, tr_note = infer_tr_seconds(d)
    fa, fa_note = infer_fa_degrees(d)
    return tr_s, fa, f"{tr_note}; {fa_note}"


# -------------------------
# VFA regression
# -------------------------

def build_default_mask(vols: List[np.ndarray], frac: float = 0.05) -> np.ndarray:
    comb = np.maximum.reduce(vols)
    comb = comb[np.isfinite(comb)]
    if comb.size == 0:
        return np.zeros(vols[0].shape, dtype=np.uint8)
    p = np.percentile(comb, 95)
    thr = frac * p
    return (np.maximum.reduce(vols) > thr).astype(np.uint8)


def vfa_fit_e1_least_squares(
    vols: List[np.ndarray],
    fas_deg: List[float],
    mask: Optional[np.ndarray],
    e1_min: float,
    e1_max: float,
) -> Tuple[np.ndarray, np.ndarray]:
    """
    Fit E1 (slope) and intercept voxelwise using OLS for y = E1*x + b.
    Returns (E1, b). Voxels failing mask get E1=nan, b=nan.
    """
    n = len(vols)
    if n < 2:
        raise ValueError("Need at least 2 flip angles.")

    shape = vols[0].shape
    for v in vols[1:]:
        if v.shape != shape:
            raise ValueError("All volumes must have same shape.")

    fas = np.deg2rad(np.array(fas_deg, dtype=np.float64))
    if np.any(fas <= 0) or np.any(fas >= np.pi):
        raise ValueError("Flip angles must be in (0,180) degrees.")
    sin_a = np.sin(fas)
    tan_a = np.tan(fas)

    # Stack into (n, vox)
    V = np.stack([v.astype(np.float64, copy=False) for v in vols], axis=0)
    vox = np.prod(shape)
    V2 = V.reshape((n, vox))

    X = (V2 / tan_a[:, None])
    Y = (V2 / sin_a[:, None])

    # Build good mask: positive signals across angles and finite
    good = np.all(np.isfinite(X) & np.isfinite(Y), axis=0) & np.all(V2 > 0, axis=0)
    if mask is not None:
        good &= (mask.reshape(vox) != 0)

    E1 = np.full(vox, np.nan, dtype=np.float64)
    b = np.full(vox, np.nan, dtype=np.float64)

    # OLS slope/intercept per voxel:
    # E1 = cov(X,Y)/var(X)
    # b  = mean(Y) - E1*mean(X)
    Xg = X[:, good]
    Yg = Y[:, good]

    Xm = np.mean(Xg, axis=0)
    Ym = np.mean(Yg, axis=0)
    Xc = Xg - Xm
    Yc = Yg - Ym

    varX = np.sum(Xc * Xc, axis=0)
    covXY = np.sum(Xc * Yc, axis=0)

    # Avoid divide-by-zero (ill-conditioned when angles are too close / saturated)
    ok = varX > 0
    e1 = np.full(Xm.shape, np.nan, dtype=np.float64)
    e1[ok] = covXY[ok] / varX[ok]
    e1 = np.clip(e1, e1_min, e1_max)

    bb = Ym - e1 * Xm

    E1[good] = e1
    b[good] = bb

    return E1.reshape(shape), b.reshape(shape)


def e1_to_t1(E1: np.ndarray, tr_s: float, fill: float = 0.0) -> np.ndarray:
    T1 = np.full(E1.shape, fill, dtype=np.float64)
    good = np.isfinite(E1) & (E1 > 0) & (E1 < 1)
    T1[good] = -tr_s / np.log(E1[good])
    return T1


def load_nifti(path: str) -> Tuple[np.ndarray, nib.Nifti1Image]:
    img = nib.load(path)
    data = img.get_fdata(dtype=np.float32)
    return data, img


# -------------------------
# CLI
# -------------------------

def parse_args():
    ap = argparse.ArgumentParser(description="Multi-flip-angle VFA T1 mapping (2+ angles) with optional Bruker .method parsing.")
    ap.add_argument("--imgs", nargs="+", required=True, help="List of NIfTI images at different flip angles (2 or more).")
    ap.add_argument("--out", required=True, help="Output T1 map NIfTI (.nii or .nii.gz)")

    ap.add_argument("--fas", nargs="+", type=float, default=None, help="Flip angles in degrees, same count/order as --imgs")
    ap.add_argument("--tr", type=float, default=None, help="TR value (optional if parsed)")
    ap.add_argument("--tr-units", choices=["s", "ms"], default="s", help="Units for --tr if provided manually (default s)")

    ap.add_argument("--methods", nargs="+", default=None, help="Optional explicit .method files (same count/order as --imgs). If omitted, uses adjacent basename.method")

    ap.add_argument("--mask", default=None, help="Optional binary mask NIfTI")
    ap.add_argument("--auto-mask", action="store_true", help="Build a simple intensity mask if no --mask provided")
    ap.add_argument("--auto-mask-frac", type=float, default=0.05, help="Auto-mask threshold fraction of 95th percentile")

    ap.add_argument("--e1-min", type=float, default=1e-6)
    ap.add_argument("--e1-max", type=float, default=0.999999)

    ap.add_argument("--require-same-tr", action="store_true", help="If TR is parsed from multiple methods, require they match.")

    return ap.parse_args()


def main():
    args = parse_args()

    if len(args.imgs) < 2:
        raise SystemExit("ERROR: Provide at least 2 images via --imgs")

    # Load images
    vols = []
    ref_img = None
    for p in args.imgs:
        v, im = load_nifti(p)
        if ref_img is None:
            ref_img = im
            ref_shape = v.shape
        else:
            if v.shape != ref_shape:
                raise SystemExit(f"ERROR: Shape mismatch: {p} has {v.shape}, expected {ref_shape}")
        vols.append(v)

    # Mask
    mask = None
    if args.mask:
        m, _ = load_nifti(args.mask)
        if m.shape != ref_shape:
            raise SystemExit(f"ERROR: Mask shape {m.shape} != image shape {ref_shape}")
        mask = (m != 0).astype(np.uint8)
    elif args.auto_mask:
        mask = build_default_mask(vols, frac=args.auto_mask_frac)

    # Resolve TR
    tr_s = None
    if args.tr is not None:
        tr_s = args.tr / 1000.0 if args.tr_units == "ms" else args.tr

    # Resolve flip angles
    fas = args.fas[:] if args.fas is not None else None
    if fas is not None and len(fas) != len(args.imgs):
        raise SystemExit("ERROR: --fas count must match --imgs count")

    # Method files
    methods = args.methods[:] if args.methods is not None else None
    if methods is not None and len(methods) != len(args.imgs):
        raise SystemExit("ERROR: --methods count must match --imgs count")

    details = []
    parsed_trs = []
    if (tr_s is None) or (fas is None):
        inferred_fas = []
        for i, img_path in enumerate(args.imgs):
            mpath = methods[i] if methods is not None else default_adjacent_method_path(img_path)
            if not os.path.isfile(mpath):
                details.append(f"[method {i}] not found: {mpath}")
                inferred_fas.append(None)
                continue
            t, f, det = infer_tr_fa_from_method(mpath)
            details.append(f"[method {i}] {mpath}: {det}")
            parsed_trs.append(t)
            inferred_fas.append(f)

        if tr_s is None:
            # Use first non-None TR
            tr_s = next((t for t in parsed_trs if t is not None), None)

        if fas is None:
            fas = inferred_fas

    # Validate TR
    if tr_s is None:
        raise SystemExit("ERROR: TR missing. Provide --tr or ensure method files contain TR.")
    if tr_s <= 0:
        raise SystemExit(f"ERROR: TR must be > 0; got {tr_s}")

    # Validate FAs
    if fas is None or any(f is None for f in fas):
        missing_idx = [i for i, f in enumerate(fas or []) if f is None]
        msg = [
            "ERROR: Flip angle(s) missing.",
            "Provide --fas (degrees) matching --imgs OR ensure method files contain flip angles.",
            f"Missing indices: {missing_idx}",
            "",
            "Method parsing diagnostics:",
            *details,
        ]
        raise SystemExit("\n".join(msg))

    # Optional TR consistency check across methods
    if args.require_same_tr:
        non_none_trs = [t for t in parsed_trs if t is not None]
        if len(non_none_trs) >= 2:
            for t in non_none_trs[1:]:
                if not np.isclose(non_none_trs[0], t, rtol=1e-6, atol=1e-9):
                    raise SystemExit(
                        "ERROR: TR mismatch across methods. Provide --tr explicitly or omit --require-same-tr.\n"
                        + "\n".join(details)
                    )

    # Fit E1 and compute T1
    E1, intercept = vfa_fit_e1_least_squares(
        vols=vols,
        fas_deg=[float(f) for f in fas],
        mask=mask,
        e1_min=args.e1_min,
        e1_max=args.e1_max,
    )
    T1 = e1_to_t1(E1, tr_s=tr_s, fill=0.0).astype(np.float32)

    out_img = nib.Nifti1Image(T1, affine=ref_img.affine, header=ref_img.header)
    out_img.header.set_data_dtype(np.float32)
    nib.save(out_img, args.out)

    print("=== Multi-angle VFA T1 mapping ===")
    print(f"TR  : {tr_s:.6g} s")
    print(f"FAs : {', '.join(str(f) for f in fas)} deg")
    print(f"Imgs: {len(args.imgs)}")
    print(f"Out : {args.out}")
    if args.mask:
        print(f"Mask: {args.mask}")
    elif args.auto_mask:
        print(f"Mask: auto (frac={args.auto_mask_frac})")
    else:
        print("Mask: none")
    if details:
        print("--- method parsing ---")
        for d in details:
            print(d)
    print("Done.")


if __name__ == "__main__":
    main()

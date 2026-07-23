#!/usr/bin/env python3

import argparse
import sys

import nibabel as nib
import numpy as np


def load_image(path):
    img = nib.load(path)
    data = img.get_fdata(dtype=np.float32)

    if data.ndim != 3:
        raise ValueError(f"{path}: expected a 3D image, got shape {data.shape}")

    return img, data


def check_same_grid(img1, img2, name1, name2):
    if img1.shape != img2.shape:
        raise ValueError(
            f"Grid mismatch:\n"
            f"  {name1}: {img1.shape}\n"
            f"  {name2}: {img2.shape}"
        )

    if not np.allclose(img1.affine, img2.affine, atol=1e-4):
        raise ValueError(
            f"{name1} and {name2} do not have matching affines.\n"
            "They must already be on the same voxel grid for mask-based matching."
        )


def percentile_mask(data, explicit_mask=None):
    if explicit_mask is not None:
        return (
            np.isfinite(data)
            & np.isfinite(explicit_mask)
            & (explicit_mask > 0)
        )

    return np.isfinite(data) & (data > 0)


def reverse_quantile_map(
    source_values,
    target_values,
    n_quantiles=1001,
    source_low=0.5,
    source_high=99.5,
    target_low=0.5,
    target_high=99.5,
):
    source_values = np.asarray(source_values, dtype=np.float64)
    target_values = np.asarray(target_values, dtype=np.float64)

    if source_values.size < 10:
        raise ValueError("Source mask contains too few voxels.")

    if target_values.size < 10:
        raise ValueError("Target mask contains too few voxels.")

    source_limits = np.percentile(
        source_values,
        [source_low, source_high],
    )
    target_limits = np.percentile(
        target_values,
        [target_low, target_high],
    )

    source_clipped = np.clip(
        source_values,
        source_limits[0],
        source_limits[1],
    )
    target_clipped = np.clip(
        target_values,
        target_limits[0],
        target_limits[1],
    )

    probabilities = np.linspace(0.0, 1.0, n_quantiles)

    source_quantiles = np.quantile(source_clipped, probabilities)

    # Reverse the target distribution:
    # source percentile q maps to target percentile 1-q.
    target_quantiles_reversed = np.quantile(
        target_clipped,
        1.0 - probabilities,
    )

    # np.interp requires monotonically increasing x coordinates.
    # Repeated source quantiles can occur in discretized images, so retain
    # one mapping value for each unique source intensity.
    unique_source, unique_indices = np.unique(
        source_quantiles,
        return_index=True,
    )
    unique_target = target_quantiles_reversed[unique_indices]

    if unique_source.size < 2:
        raise ValueError(
            "Source intensities do not contain enough variation "
            "for histogram matching."
        )

    mapped = np.interp(
        source_clipped,
        unique_source,
        unique_target,
        left=unique_target[0],
        right=unique_target[-1],
    )

    return mapped.astype(np.float32)


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Reverse-histogram-match a source image to a target image while "
            "preserving zero-valued background."
        )
    )

    parser.add_argument(
        "source",
        help="Source image whose contrast will be reversed, e.g. T2.",
    )
    parser.add_argument(
        "target",
        help="Target image whose histogram will be matched, e.g. T1.",
    )
    parser.add_argument(
        "output",
        help="Output reverse-matched source image.",
    )
    parser.add_argument(
        "--source-mask",
        help="Foreground/brain mask for the source image.",
    )
    parser.add_argument(
        "--target-mask",
        help="Foreground/brain mask for the target image.",
    )
    parser.add_argument(
        "--quantiles",
        type=int,
        default=1001,
        help="Number of quantile samples. Default: 1001.",
    )
    parser.add_argument(
        "--source-percentiles",
        type=float,
        nargs=2,
        metavar=("LOW", "HIGH"),
        default=(0.5, 99.5),
        help="Source clipping percentiles. Default: 0.5 99.5.",
    )
    parser.add_argument(
        "--target-percentiles",
        type=float,
        nargs=2,
        metavar=("LOW", "HIGH"),
        default=(0.5, 99.5),
        help="Target clipping percentiles. Default: 0.5 99.5.",
    )

    args = parser.parse_args()

    try:
        source_img, source = load_image(args.source)
        target_img, target = load_image(args.target)

        source_mask_data = None
        if args.source_mask:
            source_mask_img, source_mask_data = load_image(args.source_mask)
            check_same_grid(
                source_img,
                source_mask_img,
                args.source,
                args.source_mask,
            )

        target_mask_data = None
        if args.target_mask:
            target_mask_img, target_mask_data = load_image(args.target_mask)
            check_same_grid(
                target_img,
                target_mask_img,
                args.target,
                args.target_mask,
            )

        source_mask = percentile_mask(source, source_mask_data)
        target_mask = percentile_mask(target, target_mask_data)

        print(
            f"Source foreground voxels: {np.count_nonzero(source_mask)}",
            file=sys.stderr,
        )
        print(
            f"Target foreground voxels: {np.count_nonzero(target_mask)}",
            file=sys.stderr,
        )

        mapped_values = reverse_quantile_map(
            source[source_mask],
            target[target_mask],
            n_quantiles=args.quantiles,
            source_low=args.source_percentiles[0],
            source_high=args.source_percentiles[1],
            target_low=args.target_percentiles[0],
            target_high=args.target_percentiles[1],
        )

        output = np.zeros(source.shape, dtype=np.float32)
        output[source_mask] = mapped_values

        header = source_img.header.copy()
        header.set_data_dtype(np.float32)

        output_img = nib.Nifti1Image(
            output,
            source_img.affine,
            header,
        )

        nib.save(output_img, args.output)

    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
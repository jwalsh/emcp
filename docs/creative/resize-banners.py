#!/usr/bin/env python3
"""Crop and resize raw 1024x1024 banner images to target sizes for different contexts."""

import os
import sys
import time
from PIL import Image

VARIANTS = ["protocol", "obarray", "database"]
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# Target sizes: (name, target_width, target_height, crop_from_1024)
# crop_from_1024 = (left, upper, right, lower) on the 1024x1024 source
TARGETS = [
    # GitHub README social preview: 1280x640 (2:1) — crop center 1024x512, upscale
    ("social", 1280, 640, (0, 256, 1024, 768)),
    # README inline banner: 800x200 (4:1) — crop center strip
    ("readme", 800, 200, (0, 362, 1024, 662)),  # 300px tall strip -> scale to 800x200
    # Presentation title slide: 1920x1080 (16:9) — crop to 1024x576, upscale
    ("presentation", 1920, 1080, (0, 224, 1024, 800)),
    # GitHub repo social image: same as social preview
    ("github-social", 1280, 640, (0, 256, 1024, 768)),
    # org-mode inline: 600x200 (3:1) — crop center strip, downscale
    ("orgmode", 600, 200, (0, 362, 1024, 662)),
]


def process_variant(variant):
    raw_path = os.path.join(BASE_DIR, f"banner-{variant}-raw.png")
    if not os.path.exists(raw_path):
        print(f"  SKIP: {raw_path} not found")
        return []

    img = Image.open(raw_path)
    print(f"  Source: {raw_path} ({img.size[0]}x{img.size[1]})")
    results = []

    for name, target_w, target_h, crop_box in TARGETS:
        out_path = os.path.join(BASE_DIR, f"banner-{variant}-{name}.png")
        cropped = img.crop(crop_box)
        resized = cropped.resize((target_w, target_h), Image.LANCZOS)
        resized.save(out_path, "PNG")
        file_size = os.path.getsize(out_path)
        results.append((name, target_w, target_h, file_size, out_path))
        print(f"    {name}: {target_w}x{target_h} -> {file_size:,} bytes")

    return results


def main():
    all_results = {}
    for variant in VARIANTS:
        print(f"\nProcessing variant: {variant}")
        all_results[variant] = process_variant(variant)

    # Summary
    print("\n" + "=" * 70)
    print("SUMMARY")
    print("=" * 70)
    total_files = 0
    total_bytes = 0
    for variant, results in all_results.items():
        for name, w, h, size, path in results:
            total_files += 1
            total_bytes += size
            print(f"  banner-{variant}-{name}.png  {w}x{h}  {size:>10,} bytes")
    print(f"\nTotal: {total_files} files, {total_bytes:,} bytes ({total_bytes/1024/1024:.1f} MB)")


if __name__ == "__main__":
    main()

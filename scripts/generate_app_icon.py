#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""
generate_app_icon.py — draw the Hybrid AIthletics app icon.

A running-shoe silhouette on a plain white background, the shoe split along a
lower-left -> upper-right diagonal into electric blue and deep navy. The shoe
is described as cubic Bézier segments in a normalized space, rendered
supersampled, and downscaled for smooth edges. The result is an opaque
1024x1024 PNG written over the asset catalog's icon, so Contents.json needs no
change.

Usage:
  uv run scripts/generate_app_icon.py                   # overwrite the app icon
  uv run scripts/generate_app_icon.py --output out.png  # preview elsewhere
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
SUPERSAMPLE = 4

BACKGROUND = (255, 255, 255)
NAVY = (12, 27, 77)
ELECTRIC_BLUE = (31, 91, 255)

# The two-tone split: a line across the canvas (normalized coordinates, y down).
# Everything above/left of it is electric blue, below/right is navy.
SPLIT_FROM = (0.0, 1.0)
SPLIT_TO = (1.0, 0.06)

# Shoe placement: the profile below is drawn toe-right, then rotated (degrees,
# positive = toe tips down), scaled to this width, and centred on CENTER.
TILT_DEGREES = 10.0
SHOE_WIDTH = 0.84
CENTER = (0.5, 0.52)

# Width of the white gap separating the upper from the midsole, as a fraction
# of the canvas.
MIDSOLE_GAP = 0.018

DEFAULT_OUTPUT = (
    Path(__file__).resolve().parent.parent
    / "Hybrid AIthletics/Assets.xcassets/AppIcon.appiconset/hai-icon.png"
)

Point = tuple[float, float]

# Side profile of a running shoe, toe to the right, in a box roughly
# x 0..1, y 0..0.5 (y down). A chain of cubic Béziers: each entry is
# (control1, control2, end), starting from START.
START: Point = (0.06, 0.43)  # heel, bottom of the sole
OUTLINE: list[tuple[Point, Point, Point]] = [
    # Rocker sole from heel to toe.
    ((0.30, 0.46), (0.64, 0.46), (0.86, 0.43)),
    # Toe spring curving up and round a blunt toe cap.
    ((0.95, 0.42), (1.00, 0.38), (1.00, 0.33)),
    ((1.00, 0.27), (0.94, 0.23), (0.84, 0.21)),
    # Lace line rising to the throat.
    ((0.74, 0.19), (0.62, 0.15), (0.54, 0.09)),
    # Tongue tab.
    ((0.51, 0.04), (0.47, 0.00), (0.42, 0.01)),
    ((0.38, 0.02), (0.38, 0.08), (0.34, 0.11)),
    # Collar dipping, then the heel tab.
    ((0.28, 0.15), (0.19, 0.14), (0.14, 0.08)),
    ((0.11, 0.04), (0.07, 0.03), (0.055, 0.07)),
    # Near-vertical heel counter down to the sole.
    ((0.035, 0.14), (0.02, 0.25), (0.02, 0.33)),
    ((0.02, 0.40), (0.03, 0.43), (0.06, 0.43)),
]

# Line separating upper from midsole (same profile space), drawn in the
# background colour.
MIDSOLE_LINE: list[Point] = [(-0.05, 0.31), (0.20, 0.34), (0.50, 0.365), (0.80, 0.36), (0.95, 0.345), (1.10, 0.30)]


def cubic_bezier(p0: Point, p1: Point, p2: Point, p3: Point, steps: int = 64) -> list[Point]:
    """Flatten one cubic Bézier into `steps` points (excluding p0)."""
    points = []
    for i in range(1, steps + 1):
        t = i / steps
        u = 1 - t
        x = u**3 * p0[0] + 3 * u**2 * t * p1[0] + 3 * u * t**2 * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u**2 * t * p1[1] + 3 * u * t**2 * p2[1] + t**3 * p3[1]
        points.append((x, y))
    return points


def outline_points() -> list[Point]:
    """The closed shoe outline in profile space."""
    points = [START]
    for c1, c2, end in OUTLINE:
        points.extend(cubic_bezier(points[-1], c1, c2, end))
    return points


def smooth_polyline(points: list[Point], steps: int = 64) -> list[Point]:
    """A Catmull-Rom curve through `points`."""
    padded = [points[0], *points, points[-1]]
    result = [points[0]]
    for i in range(1, len(padded) - 2):
        p0, p1, p2, p3 = padded[i - 1], padded[i], padded[i + 1], padded[i + 2]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        result.extend(cubic_bezier(p1, c1, c2, p2, steps))
    return result


def stroke_polygon(points: list[Point], width: float) -> list[Point]:
    """A closed polygon covering a `width`-thick stroke along `points`.

    Offsets each point along its local normal, which avoids the ragged joints
    of a thick `ImageDraw.line`.
    """
    left, right = [], []
    half = width / 2
    for i, (x, y) in enumerate(points):
        ax, ay = points[max(i - 1, 0)]
        bx, by = points[min(i + 1, len(points) - 1)]
        tx, ty = bx - ax, by - ay
        length = math.hypot(tx, ty) or 1.0
        nx, ny = -ty / length * half, tx / length * half
        left.append((x + nx, y + ny))
        right.append((x - nx, y - ny))
    return left + right[::-1]


def place(points: list[Point], canvas: int) -> list[Point]:
    """Rotate, scale and centre profile-space points onto the canvas (pixels)."""
    xs = [p[0] for p in outline_points()]
    ys = [p[1] for p in outline_points()]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    scale = SHOE_WIDTH * canvas / (max(xs) - min(xs))
    angle = math.radians(TILT_DEGREES)
    cos_a, sin_a = math.cos(angle), math.sin(angle)
    placed = []
    for x, y in points:
        dx, dy = (x - cx) * scale, (y - cy) * scale
        rx, ry = dx * cos_a - dy * sin_a, dx * sin_a + dy * cos_a
        placed.append((rx + CENTER[0] * canvas, ry + CENTER[1] * canvas))
    return placed


def render(size: int = SIZE, supersample: int = SUPERSAMPLE) -> Image.Image:
    """Draw the icon and return it as an opaque RGB image of `size` pixels."""
    canvas = size * supersample

    # Silhouette mask, with the midsole gap cut back out.
    mask = Image.new("L", (canvas, canvas), 0)
    draw = ImageDraw.Draw(mask)
    draw.polygon(place(outline_points(), canvas), fill=255)
    draw.polygon(stroke_polygon(place(smooth_polyline(MIDSOLE_LINE), canvas), MIDSOLE_GAP * canvas), fill=0)

    # Two-tone fill: navy everywhere, electric blue above the split line.
    fill = Image.new("RGB", (canvas, canvas), NAVY)
    (x0, y0), (x1, y1) = SPLIT_FROM, SPLIT_TO
    # Extend the line well past the canvas so the polygon covers the corner.
    dx, dy = x1 - x0, y1 - y0
    far_a = ((x0 - dx * 4) * canvas, (y0 - dy * 4) * canvas)
    far_b = ((x1 + dx * 4) * canvas, (y1 + dy * 4) * canvas)
    upper_left = (-4 * canvas, -4 * canvas)
    ImageDraw.Draw(fill).polygon([far_a, far_b, upper_left], fill=ELECTRIC_BLUE)

    icon = Image.new("RGB", (canvas, canvas), BACKGROUND)
    icon.paste(fill, (0, 0), mask)
    return icon.resize((size, size), Image.LANCZOS)


def main() -> None:
    """Parse arguments, render the icon, and save it."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help="PNG path to write")
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    render().save(args.output, "PNG", optimize=True)
    print(args.output)


if __name__ == "__main__":
    main()

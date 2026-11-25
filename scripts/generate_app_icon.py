#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""
generate_app_icon.py — draw the Train app icon.

A small, sleek racing-shoe silhouette tucked into the top-right corner of a
plain white background (placed like the heart in Apple's Health icon): low upper, flared
heel tab, thick rocker midsole with aggressive toe spring. The shoe is two
colours, split along a configurable curve (today the midsole line): a deep
navy upper over a neon cyan midsole, with a tapered white cut between them and
tapered speed slashes cut into the heel. The navy has a subtle top-to-bottom
gradient, the neon a glossy gradient with a specular streak.

Beneath it floats a tilted dumbbell (navy handle, navy inner and neon outer
weights), so the mark is hybrid: run *and* lift. It is raised until it sits a
fixed gap from the shoe in every direction, nesting the toe in the angle
between handle and plate. Shoe and dumbbell cast one soft drop shadow. Shapes
are cubic Béziers in a normalized profile space,
rendered supersampled and downscaled for smooth edges. The result is an
opaque 1024x1024 PNG written over the asset catalog's icon, so Contents.json
needs no change.

Usage:
  uv run scripts/generate_app_icon.py                   # overwrite the app icon
  uv run scripts/generate_app_icon.py --output out.png  # preview elsewhere
"""

from __future__ import annotations

import argparse
import math
from collections.abc import Callable
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SIZE = 1024
SUPERSAMPLE = 4

BACKGROUND = (255, 255, 255)
NAVY = (10, 22, 64)
# The navy runs in a subtle vertical gradient from NAVY_TOP down to NAVY.
NAVY_TOP = (28, 48, 112)
NEON = (0, 217, 255)
# The neon midsole is glossy: a vertical gradient (fraction of its height,
# colour) from a near-white top through NEON to a deeper cyan, plus a soft
# specular streak running along its top edge.
NEON_STOPS: list[tuple[float, tuple[int, int, int]]] = [
    (0.0, (100, 232, 255)),
    (0.40, NEON),
    (1.0, (0, 150, 230)),
]

# Shoe placement: the profile below is drawn toe-right, then rotated (degrees,
# positive = toe tips down), scaled to this canvas-width fraction, and centred.
TILT_DEGREES = 6.0
SHOE_WIDTH = 0.38
CENTER = (0.58, 0.22)

# Colour split, in the same profile space as the outline: a curve through the
# shoe, and the side of it that is NEON (everything else is NAVY). The curve is
# closed off through NEON_SIDE, a point far outside the shoe on the neon side.
# It follows the midsole cut, so the upper is navy and the midsole neon.
SPLIT_CURVE: list[Point] = [
    (-0.5, 0.33), (-0.03, 0.335), (0.25, 0.375), (0.55, 0.385), (0.80, 0.36), (1.03, 0.29), (1.5, 0.20),
]
NEON_SIDE: Point = (0.5, 3.0)
# Width of a white cut along the split (0 = none; the midsole cut already
# separates the two colours).
SPLIT_GAP = 0.0

# Soft drop shadow under the shoe (fractions of the canvas; opacity 0..1).
SHADOW_COLOR = NAVY
SHADOW_OPACITY = 0.24
SHADOW_BLUR = 0.018
SHADOW_OFFSET = (0.0, 0.022)

# Specular streak on the midsole: (points, peak width) in profile space,
# tapering to nothing at both ends, blurred by HIGHLIGHT_BLUR.
HIGHLIGHT: tuple[list[Point], float] = (
    [(0.10, 0.392), (0.30, 0.420), (0.55, 0.428), (0.78, 0.408), (0.91, 0.368)],
    0.010,
)
HIGHLIGHT_COLOR = (255, 255, 255)
HIGHLIGHT_OPACITY = 0.85
HIGHLIGHT_BLUR = 0.003

# Dumbbell floating under the shoe, so the mark says run *and* lift while
# staying compact enough for the corner. Parts are in dumbbell units, scaled so
# the whole dumbbell spans DUMBBELL_SPAN x the shoe's width; it is centred
# under the shoe (plus DUMBBELL_SHIFT), tilted, then raised until it comes
# within DUMBBELL_GAP of the shoe in any direction. The handle and collars are navy.
DUMBBELL_SPAN = 1.08
DUMBBELL_GAP = 0.028  # fraction of the canvas, at the closest point
DUMBBELL_TILT = -14.0  # degrees, positive = right (toe) end down
DUMBBELL_SHIFT = 0.12  # horizontal nudge from the shoe's centre (+ = toward the toe)
HANDLE_LENGTH = 0.240  # between the collars
HANDLE_THICKNESS = 0.026
COLLAR: tuple[float, float] = (0.016, 0.055)  # (width, height)
WEIGHTS: list[tuple[float, float]] = [(0.060, 0.190), (0.038, 0.135)]  # (width, height), inner -> outer
WEIGHT_SPACING = 0.006
WEIGHT_RADIUS = 0.014
# One gradient per entry in WEIGHTS (inner -> outer): NAVY_RAMP sets a plate
# apart from the midsole, NEON_STOPS ties it to it.
NAVY_RAMP: list[tuple[float, tuple[int, int, int]]] = [(0.0, NAVY_TOP), (1.0, NAVY)]
WEIGHT_STOPS: list[list[tuple[float, tuple[int, int, int]]]] = [NAVY_RAMP, NEON_STOPS]
# Specular streak down each weight's left side: (inset from the left edge,
# width), in dumbbell units.
WEIGHT_HIGHLIGHT: tuple[float, float] = (0.010, 0.009)

DEFAULT_OUTPUT = (
    Path(__file__).resolve().parent.parent
    / "Train/Assets.xcassets/AppIcon.appiconset/app-icon.png"
)

Point = tuple[float, float]

# Side profile, toe right, y down. A chain of cubic Béziers: each entry is
# (control1, control2, end), starting from START.
START: Point = (0.10, 0.47)  # heel, where the sole meets the ground
OUTLINE: list[tuple[Point, Point, Point]] = [
    # Rocker sole sweeping up into a steep toe spring.
    ((0.38, 0.51), (0.70, 0.49), (0.88, 0.42)),
    ((0.95, 0.39), (1.00, 0.34), (0.995, 0.30)),
    # Rounded toe box.
    ((0.99, 0.24), (0.94, 0.21), (0.86, 0.20)),
    # Lace line rising to a small tongue.
    ((0.74, 0.185), (0.60, 0.14), (0.50, 0.085)),
    ((0.47, 0.06), (0.43, 0.055), (0.41, 0.075)),
    # Low collar.
    ((0.35, 0.14), (0.25, 0.155), (0.18, 0.11)),
    # Heel tab flaring up and back to a point.
    ((0.14, 0.085), (0.10, 0.06), (0.055, 0.055)),
    ((0.065, 0.10), (0.06, 0.18), (0.045, 0.25)),
    # Heel counter into a midsole that flares out behind the heel.
    ((0.035, 0.29), (0.00, 0.32), (0.00, 0.37)),
    ((0.00, 0.43), (0.04, 0.461), (0.10, 0.47)),
]

# White cut between upper and midsole: (points, width at start, width at end)
# as fractions of the canvas. Tapering heel -> toe keeps it from looking like a
# rule drawn across the shoe.
MIDSOLE_CUT: tuple[list[Point], float, float] = (
    [(-0.03, 0.335), (0.25, 0.375), (0.55, 0.385), (0.80, 0.36), (1.03, 0.29)],
    0.020,
    0.008,
)

# Speed slashes cut into the heel: start fat at the back, taper to a point.
SPEED_SLASHES: list[tuple[list[Point], float, float]] = [
    ([(-0.02, 0.235), (0.18, 0.250), (0.36, 0.272)], 0.020, 0.0),
    ([(-0.02, 0.288), (0.14, 0.302), (0.27, 0.318)], 0.016, 0.0),
]


def cubic_bezier(p0: Point, p1: Point, p2: Point, p3: Point, steps: int = 96) -> list[Point]:
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


def smooth_polyline(points: list[Point], steps: int = 96) -> list[Point]:
    """A Catmull-Rom curve through `points`."""
    padded = [points[0], *points, points[-1]]
    result = [points[0]]
    for i in range(1, len(padded) - 2):
        p0, p1, p2, p3 = padded[i - 1], padded[i], padded[i + 1], padded[i + 2]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        result.extend(cubic_bezier(p1, c1, c2, p2, steps))
    return result


def stroke_polygon(points: list[Point], width: Callable[[float], float]) -> list[Point]:
    """A closed polygon covering a stroke along `points`.

    `width(t)` gives the stroke width at fraction t (0..1) along the line, so a
    stroke can taper. Offsetting along local normals avoids the ragged joints
    of a thick `ImageDraw.line`.
    """
    left, right = [], []
    last = len(points) - 1
    for i, (x, y) in enumerate(points):
        ax, ay = points[max(i - 1, 0)]
        bx, by = points[min(i + 1, last)]
        tx, ty = bx - ax, by - ay
        length = math.hypot(tx, ty) or 1.0
        half = width(i / last) / 2
        nx, ny = -ty / length * half, tx / length * half
        left.append((x + nx, y + ny))
        right.append((x - nx, y - ny))
    return left + right[::-1]


def place(points: list[Point], canvas: int) -> list[Point]:
    """Rotate, scale and centre profile-space points onto the canvas (pixels)."""
    outline = outline_points()
    xs = [p[0] for p in outline]
    ys = [p[1] for p in outline]
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


def cut_tapered(draw: ImageDraw.ImageDraw, cut: tuple[list[Point], float, float], canvas: int) -> None:
    """Erase a tapered stroke (profile-space points) from the mask."""
    points, start, end = cut
    path = place(smooth_polyline(points), canvas)
    draw.polygon(stroke_polygon(path, lambda t: (start + (end - start) * t) * canvas), fill=0)


def vertical_gradient(
    canvas: int,
    bbox: tuple[int, int, int, int] | None,
    stops: list[tuple[float, tuple[int, int, int]]],
) -> Image.Image:
    """A canvas-sized RGB image graded top to bottom across `bbox`'s height.

    `stops` are (fraction of the height, colour) pairs in ascending order;
    rows above or below the box take the first or last colour.
    """
    y0, y1 = (bbox[1], bbox[3]) if bbox else (0, canvas)
    height = max(y1 - y0, 1)
    column = Image.new("RGB", (1, canvas))
    pixels = column.load()
    for y in range(canvas):
        t = min(max((y - y0) / height, 0.0), 1.0)
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t <= t1:
                k = (t - t0) / ((t1 - t0) or 1.0)
                pixels[0, y] = tuple(round(a + (b - a) * k) for a, b in zip(c0, c1))
                break
        else:
            pixels[0, y] = stops[-1][1]
    return column.resize((canvas, canvas))


def drop_shadow(mask: Image.Image, canvas: int) -> Image.Image:
    """The shadow's alpha: the silhouette offset, blurred, and faded to SHADOW_OPACITY."""
    dx, dy = (round(o * canvas) for o in SHADOW_OFFSET)
    shadow = ImageChops.offset(mask, dx, dy).filter(ImageFilter.GaussianBlur(SHADOW_BLUR * canvas))
    return shadow.point(lambda v: round(v * SHADOW_OPACITY))


Box = tuple[float, float, float, float]


def dumbbell_boxes(canvas: int, center: Point) -> tuple[list[Box], list[list[Box]], float]:
    """The level dumbbell as pixel boxes around `center`.

    Returns (navy handle + collars, weight boxes grouped by WEIGHTS index, and
    the pixels per dumbbell unit).
    """
    units = HANDLE_LENGTH + 2 * (COLLAR[0] + sum(w for w, _ in WEIGHTS) + WEIGHT_SPACING * (len(WEIGHTS) - 1))
    scale = DUMBBELL_SPAN * SHOE_WIDTH * canvas / units
    cx, cy = center
    span = lambda x0, x1, height: (min(x0, x1), cy - height * scale / 2, max(x0, x1), cy + height * scale / 2)

    navy = [span(cx - HANDLE_LENGTH * scale / 2, cx + HANDLE_LENGTH * scale / 2, HANDLE_THICKNESS)]
    weights: list[list[Box]] = [[] for _ in WEIGHTS]
    for side in (-1, 1):
        edge = cx + side * HANDLE_LENGTH * scale / 2
        outer = edge + side * COLLAR[0] * scale
        navy.append(span(edge, outer, COLLAR[1]))
        edge = outer
        for i, (width, height) in enumerate(WEIGHTS):
            outer = edge + side * width * scale
            weights[i].append(span(edge, outer, height))
            edge = outer + side * WEIGHT_SPACING * scale
    return navy, weights, scale


def clearance_zone(solid: Image.Image, gap: float, work: int = 1024) -> Image.Image:
    """`solid` grown by `gap` pixels in every direction, at `work` resolution.

    Anything outside this mask is at least `gap` away from the shoe. Grown by
    repeated 3x3 max filters, which is quick at the reduced size.
    """
    small = solid.resize((work, work), Image.BILINEAR).point(lambda v: 255 if v else 0)
    for _ in range(max(round(gap * work / solid.width), 1)):
        small = small.filter(ImageFilter.MaxFilter(3))
    return small


def render_dumbbell(canvas: int, solid: Image.Image) -> tuple[Image.Image, Image.Image]:
    """Draw the tilted dumbbell under the shoe: returns (its fill, its mask).

    Drawn level around the canvas centre, rotated by DUMBBELL_TILT, then
    raised from below until it comes within DUMBBELL_GAP of the shoe's
    silhouette (`solid`) in any direction.
    """
    shoe_box = solid.getbbox()
    pivot = ((shoe_box[0] + shoe_box[2]) / 2 + DUMBBELL_SHIFT * canvas, canvas / 2)
    navy_boxes, weight_groups, scale = dumbbell_boxes(canvas, pivot)

    handle = Image.new("L", (canvas, canvas), 0)
    for box in navy_boxes:
        ImageDraw.Draw(handle).rectangle(box, fill=255)
    gloss = Image.new("L", (canvas, canvas), 0)
    inset, width = (v * scale for v in WEIGHT_HIGHLIGHT)
    plates = []
    for boxes in weight_groups:
        plate = Image.new("L", (canvas, canvas), 0)
        for x0, y0, x1, y1 in boxes:
            ImageDraw.Draw(plate).rounded_rectangle((x0, y0, x1, y1), radius=WEIGHT_RADIUS * scale, fill=255)
            pad = (y1 - y0) * 0.18
            ImageDraw.Draw(gloss).rounded_rectangle(
                (x0 + inset, y0 + pad, x0 + inset + width, y1 - pad), radius=width / 2, fill=255
            )
        plates.append(plate)

    # Tilt every layer about the pivot (PIL rotates counter-clockwise).
    tilt = lambda im: im.rotate(-DUMBBELL_TILT, resample=Image.BICUBIC, center=pivot)
    handle, gloss, plates = tilt(handle), tilt(gloss), [tilt(p) for p in plates]
    weights_mask = Image.new("L", (canvas, canvas), 0)
    for plate in plates:
        weights_mask = ImageChops.lighter(weights_mask, plate)
    shape = ImageChops.lighter(handle, weights_mask)

    # Start well below the shoe and raise the dumbbell until any part of it
    # would come within DUMBBELL_GAP of the shoe, in any direction. A dumbbell
    # shifted past the toe can therefore rise beside it, nesting the shoe in
    # the angle between handle and plate.
    work = 1024
    zone = clearance_zone(solid, DUMBBELL_GAP * canvas, work)
    small = shape.resize((work, work), Image.BILINEAR).point(lambda v: 255 if v else 0)
    small_box = small.getbbox()
    step = canvas // work
    start = zone.getbbox()[3] - small_box[1] + 1  # dumbbell's top just below the zone
    dy_small = start
    while small_box[1] + dy_small - 1 > 0:
        moved = ImageChops.offset(small, 0, dy_small - 1)
        if ImageChops.multiply(moved, zone).getbbox():
            break
        dy_small -= 1
    dy = dy_small * step
    drop = lambda im: ImageChops.offset(im, 0, dy)
    handle, gloss, shape, weights_mask = drop(handle), drop(gloss), drop(shape), drop(weights_mask)
    plates = [drop(p) for p in plates]

    fill = vertical_gradient(canvas, handle.getbbox(), NAVY_RAMP)
    for plate, stops in zip(plates, WEIGHT_STOPS):
        fill.paste(vertical_gradient(canvas, plate.getbbox(), stops), (0, 0), plate)
    gloss = ImageChops.multiply(gloss.filter(ImageFilter.GaussianBlur(HIGHLIGHT_BLUR * canvas)), weights_mask)
    fill.paste(HIGHLIGHT_COLOR, (0, 0), gloss.point(lambda v: round(v * HIGHLIGHT_OPACITY)))
    return fill, shape


def render(size: int = SIZE, supersample: int = SUPERSAMPLE) -> Image.Image:
    """Draw the icon and return it as an opaque RGB image of `size` pixels."""
    canvas = size * supersample

    # Silhouette mask, with the negative-space cuts erased back out.
    mask = Image.new("L", (canvas, canvas), 0)
    draw = ImageDraw.Draw(mask)
    draw.polygon(place(outline_points(), canvas), fill=255)
    solid = mask.copy()  # before the cuts: casts the shadow, keeps the cuts white
    cut_tapered(draw, MIDSOLE_CUT, canvas)
    for slash in SPEED_SLASHES:
        cut_tapered(draw, slash, canvas)

    # Two-tone fill: navy everywhere, neon on one side of the split curve,
    # with a white cut along the curve itself.
    split = place(smooth_polyline(SPLIT_CURVE), canvas)
    side = place([NEON_SIDE], canvas)[0]
    fill = vertical_gradient(canvas, mask.getbbox(), [(0.0, NAVY_TOP), (1.0, NAVY)])
    neon = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(neon).polygon([*split, side], fill=255)
    neon = ImageChops.multiply(neon, mask)
    fill.paste(vertical_gradient(canvas, neon.getbbox(), NEON_STOPS), (0, 0), neon)

    # Glossy streak along the top of the midsole, clipped to it.
    points, peak = HIGHLIGHT
    streak = Image.new("L", (canvas, canvas), 0)
    path = place(smooth_polyline(points), canvas)
    ImageDraw.Draw(streak).polygon(
        stroke_polygon(path, lambda t: peak * canvas * math.sin(math.pi * t)), fill=255
    )
    streak = streak.filter(ImageFilter.GaussianBlur(HIGHLIGHT_BLUR * canvas))
    streak = ImageChops.multiply(streak, neon).point(lambda v: round(v * HIGHLIGHT_OPACITY))
    fill.paste(HIGHLIGHT_COLOR, (0, 0), streak)
    if SPLIT_GAP:
        draw.polygon(stroke_polygon(split, lambda _: SPLIT_GAP * canvas), fill=0)

    # Dumbbell floating under the shoe.
    dumbbell_fill, dumbbell = render_dumbbell(canvas, solid)

    everything = ImageChops.lighter(solid, dumbbell)
    icon = Image.new("RGB", (canvas, canvas), BACKGROUND)
    icon.paste(SHADOW_COLOR, (0, 0), drop_shadow(everything, canvas))
    icon.paste(BACKGROUND, (0, 0), everything)
    icon.paste(dumbbell_fill, (0, 0), dumbbell)
    icon.paste(BACKGROUND, (0, 0), solid)
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

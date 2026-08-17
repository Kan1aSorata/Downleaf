#!/usr/bin/env python3

from pathlib import Path
import sys

from PIL import Image, ImageDraw, ImageFont, ImageOps


def fitted_panel(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    panel = Image.new("RGB", size, "#151515")
    fitted = ImageOps.contain(image.convert("RGB"), (size[0] - 32, size[1] - 32))
    position = ((size[0] - fitted.width) // 2, (size[1] - fitted.height) // 2)
    panel.paste(fitted, position)
    return panel


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("usage: make-visual-comparison.py REFERENCE IMPLEMENTATION OUTPUT")

    reference_path, implementation_path, output_path = map(Path, sys.argv[1:])
    reference = Image.open(reference_path)
    implementation = Image.open(implementation_path)

    panel_size = (1240, 760)
    label_height = 48
    gap = 20
    margin = 20
    canvas = Image.new(
        "RGB",
        (margin * 2 + panel_size[0] * 2 + gap, margin * 2 + label_height + panel_size[1]),
        "#0b0b0b",
    )
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default(size=18)

    left_x = margin
    right_x = margin + panel_size[0] + gap
    draw.text((left_x, margin + 10), "REFERENCE PROTOTYPE", fill="#d9d9d9", font=font)
    draw.text((right_x, margin + 10), "NATIVE MACOS MVP", fill="#d9d9d9", font=font)

    canvas.paste(fitted_panel(reference, panel_size), (left_x, margin + label_height))
    canvas.paste(fitted_panel(implementation, panel_size), (right_x, margin + label_height))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output_path, quality=92)


if __name__ == "__main__":
    main()

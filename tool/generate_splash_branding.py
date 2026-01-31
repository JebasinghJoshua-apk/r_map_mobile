from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def main() -> None:
    out_path = Path("android/app/src/main/res/drawable-nodpi/splash_branding.png")
    out_path.parent.mkdir(parents=True, exist_ok=True)

    # Android's splash screen may scale branding into a fixed dp box.
    # Use a more balanced aspect ratio to avoid non-uniform scaling artifacts.
    width, height = 600, 200
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    text = "Real Estate Map"

    font = None
    for font_path in [
        "C:/Windows/Fonts/segoeuib.ttf",
        "C:/Windows/Fonts/segoeui.ttf",
        "C:/Windows/Fonts/arialbd.ttf",
        "C:/Windows/Fonts/arial.ttf",
    ]:
        try:
            font = ImageFont.truetype(font_path, 54)
            break
        except Exception:
            pass
    if font is None:
        font = ImageFont.load_default()

    # Teal similar to the app icon.
    color = (15, 173, 151, 255)

    bbox = draw.textbbox((0, 0), text, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]

    # Position the text higher within the image so it appears closer to the
    # centered app icon when Android anchors the branding image at the bottom.
    x = (width - text_w) // 2
    y = 18
    draw.text((x, y), text, font=font, fill=color)

    img.save(out_path, "PNG")
    print(f"Wrote {out_path}")


if __name__ == "__main__":
    main()

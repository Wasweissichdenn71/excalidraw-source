#!/usr/bin/env python3
import re
import sys
from pathlib import Path


def clean_svg(content: str) -> str:
    # Entfernt eingebettete Excalifont-WOFF2-Webfont-Definitionen.
    # Inkscape kann solche eingebetteten Webfont-Blöcke je nach Version problematisch behandeln.
    font_face_pattern = re.compile(
        r"@font-face\s*\{[\s\S]*?"
        r"font-family\s*:\s*Excalifont[\s\S]*?"
        r"src\s*:\s*url\(data:font/woff2;base64,[\s\S]*?\)\s*;?\s*"
        r"[\s\S]*?\}",
        flags=re.IGNORECASE,
    )

    content = font_face_pattern.sub("", content)

    # Font-Fallbacklisten auf Excalifont reduzieren.
    replacements = [
        (
            'font-family="Excalifont, Xiaolai, sans-serif, Segoe UI Emoji"',
            'font-family="Excalifont"',
        ),
        (
            "font-family='Excalifont, Xiaolai, sans-serif, Segoe UI Emoji'",
            "font-family='Excalifont'",
        ),
    ]

    for old, new in replacements:
        content = content.replace(old, new)

    content = re.sub(
        r"font-family\s*:\s*Excalifont\s*,\s*Xiaolai\s*,\s*sans-serif\s*,\s*Segoe UI Emoji",
        "font-family: Excalifont",
        content,
        flags=re.IGNORECASE,
    )

    return content


def main() -> None:
    if len(sys.argv) != 3:
        print("Usage: clean_svg_for_inkscape.py INPUT.svg OUTPUT.svg", file=sys.stderr)
        sys.exit(2)

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])

    content = input_path.read_text(encoding="utf-8")
    cleaned = clean_svg(content)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(cleaned, encoding="utf-8")

    print(f"OK: cleaned SVG for Inkscape: {input_path} -> {output_path}")


if __name__ == "__main__":
    main()

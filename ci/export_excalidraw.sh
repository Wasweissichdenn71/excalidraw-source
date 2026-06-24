#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: export_excalidraw.sh SOURCE_ROOT OUTPUT_ROOT" >&2
  exit 2
fi

SOURCE_ROOT="$1"
OUTPUT_ROOT="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACT_SCRIPT="$SCRIPT_DIR/extract_excalidraw.py"

SOURCE_ROOT="$(realpath "$SOURCE_ROOT")"
OUTPUT_ROOT="$(realpath -m "$OUTPUT_ROOT")"

export HOME="${HOME:-/var/lib/jenkins}"
export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/var/lib/jenkins/.cache/ms-playwright}"

mkdir -p "$OUTPUT_ROOT"

echo "Source root: $SOURCE_ROOT"
echo "Output root: $OUTPUT_ROOT"
echo "Extractor:   $EXTRACT_SCRIPT"
echo "Playwright:  $PLAYWRIGHT_BROWSERS_PATH"

find "$SOURCE_ROOT" \
  \( \
    -path "$SOURCE_ROOT/.git" -o \
    -path "$SOURCE_ROOT/.obsidian" -o \
    -path "$SOURCE_ROOT/node_modules" \
  \) -prune -o \
  -type f \( -name "*.excalidraw" -o -name "*.excalidraw.md" \) -print0 |
while IFS= read -r -d '' input_file; do
  rel="${input_file#$SOURCE_ROOT/}"

  case "$rel" in
    *.excalidraw.md)
      base="${rel%.excalidraw.md}"
      ;;
    *.excalidraw)
      base="${rel%.excalidraw}"
      ;;
    *)
      continue
      ;;
  esac

  out_base="$OUTPUT_ROOT/$base"
  out_dir="$(dirname "$out_base")"

  mkdir -p "$out_dir"

  out_excalidraw="$out_base.excalidraw"
  out_svg="$out_base.svg"
  out_png="$out_base.png"
  out_pdf="$out_base.pdf"

  echo
  echo "==> Verarbeite: $rel"

  python3 "$EXTRACT_SCRIPT" "$input_file" "$out_excalidraw"

  excalidraw-brute-export-cli \
    -i "$out_excalidraw" \
    -o "$out_svg" \
    -f svg \
    -s 2 \
    -b true \
    -e true \
    -d false

  excalidraw-brute-export-cli \
    -i "$out_excalidraw" \
    -o "$out_png" \
    -f png \
    -s 2 \
    -b true \
    -e true \
    -d false

  inkscape "$out_svg" \
    --export-type=pdf \
    --export-filename="$out_pdf" \
    --export-text-to-path

  chmod 664 "$out_excalidraw" "$out_svg" "$out_png" "$out_pdf" || true

  echo "    OK: $out_excalidraw"
  echo "    OK: $out_svg"
  echo "    OK: $out_png"
  echo "    OK: $out_pdf"
done

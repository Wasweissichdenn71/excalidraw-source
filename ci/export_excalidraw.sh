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
    -path "$SOURCE_ROOT/node_modules" -o \
    -path "$SOURCE_ROOT/target" \
  \) -prune -o \
  -type f \( -name "*.excalidraw" -o -name "*.excalidraw.md" -o -name "*.md" \) -print0 |
while IFS= read -r -d '' input_file; do
  rel="${input_file#$SOURCE_ROOT/}"

  case "$rel" in
    *.excalidraw.md)
      base="${rel%.excalidraw.md}"
      strict_mode="true"
      ;;
    *.excalidraw)
      base="${rel%.excalidraw}"
      strict_mode="true"
      ;;
    *.md)
      base="${rel%.md}"
      strict_mode="false"
      ;;
    *)
      continue
      ;;
  esac

  file_stem="$(basename "$base")"
  out_dir="$OUTPUT_ROOT/$base"

  mkdir -p "$out_dir"

  out_excalidraw="$out_dir/$file_stem.excalidraw"
  out_svg="$out_dir/$file_stem.svg"
  out_png="$out_dir/$file_stem.png"
  out_pdf="$out_dir/$file_stem.pdf"

  echo
  echo "==> Verarbeite: $rel"

  if ! python3 "$EXTRACT_SCRIPT" "$input_file" "$out_excalidraw"; then
    if [ "$strict_mode" = "false" ]; then
      echo "    SKIP: Keine Excalidraw-Daten in Markdown-Datei gefunden: $rel"
      rm -f "$out_excalidraw"
      rmdir "$out_dir" 2>/dev/null || true
      continue
    else
      echo "    ERROR: Excalidraw-Datei konnte nicht gelesen werden: $rel" >&2
      exit 1
    fi
  fi

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

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

run_excalidraw_export() {
  local input_file="$1"
  local output_file="$2"
  local format="$3"

  local attempt=1
  local max_attempts=3

  while [ "$attempt" -le "$max_attempts" ]; do
    echo "    Export $format attempt $attempt/$max_attempts"

    if excalidraw-brute-export-cli \
      -i "$input_file" \
      -o "$output_file" \
      -f "$format" \
      -s 2 \
      -b true \
      -e true \
      -d false \
      --excalidraw-version 0.17.0 \
      --timeout 120000; then
      return 0
    fi

    echo "    WARN: Export $format failed on attempt $attempt"
    attempt=$((attempt + 1))
    sleep 5
  done

  echo "    ERROR: Export $format failed after $max_attempts attempts: $input_file" >&2
  return 1
}

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

  run_excalidraw_export "$out_excalidraw" "$out_svg" "svg"
  run_excalidraw_export "$out_excalidraw" "$out_png" "png"

  clean_svg="$(mktemp --suffix=.svg)"
  python3 "$SCRIPT_DIR/clean_svg_for_inkscape.py" "$out_svg" "$clean_svg"

  inkscape "$clean_svg" \
    --export-type=pdf \
    --export-filename="$out_pdf" \
    --export-area-page \
    --export-text-to-path

  rm -f "$clean_svg"

  chmod 664 "$out_excalidraw" "$out_svg" "$out_png" "$out_pdf" || true

  echo "    OK: $out_excalidraw"
  echo "    OK: $out_svg"
  echo "    OK: $out_png"
  echo "    OK: $out_pdf"
done

#!/usr/bin/env bash

# Convert PDFs to PNG and SVG with sensible defaults and fallbacks.
# Usage:
#   ./convert_pdfs.sh                # convert all PDFs in this directory
#   ./convert_pdfs.sh file1.pdf dir/ another_basename
# Env overrides:
#   PNG_DPI (default: 300)
#   PNG_QUALITY (default: 95)

set -euo pipefail

PNG_DPI=${PNG_DPI:-300}
PNG_QUALITY=${PNG_QUALITY:-95}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

have_svg_converter() {
  if command -v pdf2svg >/dev/null 2>&1; then echo pdf2svg; return 0; fi
  if command -v pdftocairo >/dev/null 2>&1; then echo pdftocairo; return 0; fi
  if command -v inkscape >/dev/null 2>&1; then echo inkscape; return 0; fi
  return 1
}

have_png_converter() {
  if command -v magick >/dev/null 2>&1; then echo magick; return 0; fi
  if command -v convert >/dev/null 2>&1; then echo convert; return 0; fi
  if command -v pdftocairo >/dev/null 2>&1; then echo pdftocairo; return 0; fi
  if command -v sips >/dev/null 2>&1; then echo sips; return 0; fi
  return 1
}

convert_pdf() {
  local input_pdf="$1"
  local dir base stem svg_out png_out out_base

  if [[ ! -f "$input_pdf" ]]; then
    echo "[skip] Not a file: $input_pdf" >&2
    return 1
  fi

  dir="$(dirname "$input_pdf")"
  base="$(basename "$input_pdf")"
  stem="${base%.pdf}"
  out_base="$dir/$stem"
  svg_out="$out_base.svg"
  png_out="$out_base.png"

  # SVG conversion
  local svg_conv
  svg_conv=$(have_svg_converter || true)
  if [[ -n "$svg_conv" ]]; then
    case "$svg_conv" in
      pdf2svg)
        pdf2svg "$input_pdf" "$svg_out"
        ;;
      pdftocairo)
        pdftocairo -svg "$input_pdf" "$out_base"
        ;;
      inkscape)
        (inkscape "$input_pdf" --export-type=svg --export-filename="$svg_out" >/dev/null 2>&1) || \
        (inkscape "$input_pdf" --export-plain-svg="$svg_out" >/dev/null 2>&1)
        ;;
    esac
    echo "[svg] $svg_out"
  else
    echo "[warn] No PDF->SVG converter (install pdf2svg or poppler)." >&2
  fi

  # PNG conversion (first page)
  local png_conv
  png_conv=$(have_png_converter || true)
  if [[ -n "$png_conv" ]]; then
    case "$png_conv" in
      magick)
        magick -density "$PNG_DPI" "$input_pdf[0]" -quality "$PNG_QUALITY" "$png_out"
        ;;
      convert)
        convert -density "$PNG_DPI" "$input_pdf[0]" -quality "$PNG_QUALITY" "$png_out"
        ;;
      pdftocairo)
        pdftocairo -png -r "$PNG_DPI" -singlefile "$input_pdf" "$out_base"
        ;;
      sips)
        sips -s format png "$input_pdf" --out "$png_out" >/dev/null
        ;;
    esac
    echo "[png] $png_out"
  else
    echo "[warn] No PDF->PNG converter (install ImageMagick or poppler)." >&2
  fi
}

collect_targets() {
  if [[ $# -eq 0 ]]; then
    # All PDFs in script directory
    shopt -s nullglob
    for f in "$SCRIPT_DIR"/*.pdf; do
      echo "$f"
    done
    shopt -u nullglob
    return 0
  fi

  local arg
  for arg in "$@"; do
    if [[ -d "$arg" ]]; then
      shopt -s nullglob
      for f in "$arg"/*.pdf; do echo "$f"; done
      shopt -u nullglob
    elif [[ -f "$arg" ]]; then
      echo "$arg"
    elif [[ -f "$SCRIPT_DIR/$arg" ]]; then
      echo "$SCRIPT_DIR/$arg"
    elif [[ -f "$SCRIPT_DIR/${arg%.pdf}.pdf" ]]; then
      echo "$SCRIPT_DIR/${arg%.pdf}.pdf"
    else
      echo "[warn] Skipping unknown target: $arg" >&2
    fi
  done
}

main() {
  local targets=("$(collect_targets "$@")")
  local any=0
  IFS=$'\n' read -r -d '' -a targets < <(collect_targets "$@"; printf '\0') || true
  if [[ ${#targets[@]} -eq 0 ]]; then
    echo "No PDFs found to convert." >&2
    exit 1
  fi
  local t
  for t in "${targets[@]}"; do
    convert_pdf "$t" || any=1
  done
  exit "$any"
}

main "$@"

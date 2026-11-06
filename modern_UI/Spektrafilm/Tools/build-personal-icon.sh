#!/bin/bash
# Package an approved square RGB PNG into a legacy .icns, without actool or
# modifying the source image. All icon sizes are rasterised from that source.
set -euo pipefail

fail() { printf 'build-personal-icon: %s\n' "$*" >&2; exit 1; }
if [[ $# -lt 2 || $# -gt 3 ]]; then
  printf 'Usage: Tools/build-personal-icon.sh INPUT_PNG OUTPUT_ICNS [WORK_ROOT]\n' >&2
  exit 2
fi
input=$1
output=$2
work_root=${3:-${TMPDIR:-/tmp}}
[[ -f "$input" ]] || fail "input does not exist: $input"
[[ ! -e "$output" && ! -L "$output" ]] || fail "output exists; retain it and choose a new output path: $output"
[[ "$output" == *.icns ]] || fail 'output must have the .icns extension'
input=$(CDPATH= cd -- "$(dirname -- "$input")" && pwd -P)/$(basename -- "$input")
metadata=$(/usr/bin/sips -g format -g space -g pixelWidth -g pixelHeight "$input")
format=$(printf '%s\n' "$metadata" | awk '$1 == "format:" {print $2}')
space=$(printf '%s\n' "$metadata" | awk '$1 == "space:" {print $2}')
width=$(printf '%s\n' "$metadata" | awk '$1 == "pixelWidth:" {print $2}')
height=$(printf '%s\n' "$metadata" | awk '$1 == "pixelHeight:" {print $2}')
[[ "$format" == png && "$space" == RGB ]] || fail 'input must be an RGB PNG'
[[ "$width" =~ ^[0-9]+$ && "$height" =~ ^[0-9]+$ ]] || fail 'cannot read image dimensions'
[[ "$width" -eq "$height" && "$width" -ge 1024 ]] || fail 'input must be square and at least 1024 × 1024 pixels'

mkdir -p "$(dirname -- "$output")"
parent=$(CDPATH= cd -- "$(dirname -- "$output")" && pwd -P)
output="$parent/$(basename -- "$output")"
mkdir -p "$work_root"
run=$(mktemp -d "$work_root/personal-icon.XXXXXX")
iconset="$run/Personal.iconset"
mkdir -p "$iconset"
for logical in 16 32 128 256 512; do
  for scale in 1 2; do
    pixels=$((logical * scale))
    suffix=""
    if [[ "$scale" -eq 2 ]]; then suffix=@2x; fi
    /usr/bin/sips --resampleHeightWidth "$pixels" "$pixels" "$input" \
      --out "$iconset/icon_${logical}x${logical}${suffix}.png" >/dev/null
  done
done
/usr/bin/iconutil --convert icns "$iconset" --output "$run/Personal.icns"
[[ -s "$run/Personal.icns" ]] || fail 'iconutil produced no icon'
# Validate the container by decoding it with the same system tool.
/usr/bin/iconutil --convert iconset "$run/Personal.icns" --output "$run/Decoded.iconset"
[[ -s "$run/Decoded.iconset/icon_512x512@2x.png" ]] || fail 'the 1024-pixel representation is missing'
shasum -a 256 "$input" "$run/Personal.icns" > "$run/provenance-sha256.txt"
printf '%s\n' "$metadata" > "$run/input-metadata.txt"
mv "$run/Personal.icns" "$output"
printf 'Personal icon: %s\nIcon inputs and decoded check: %s\n' "$output" "$run"

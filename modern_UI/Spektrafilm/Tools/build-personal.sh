#!/bin/bash
# Build the UI-only personal variant with Apple's Command Line Tools.
# Metal/asset compilers require Xcode, so this deliberately reuses the complete
# resource tree from the matching, installed 1.3.5 (20) release. It refuses
# engine, shader or bundled-resource changes: those need a normal Xcode build.
# The sole added resource is Personal.icns, built from the approved personal PNG.
# No system installation, application termination or defaults mutation occurs.
set -euo pipefail

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo=$(CDPATH= cd -- "$here/../../.." && pwd)
app_sources="$repo/modern_UI/Spektrafilm/Spektrafilm"
template_app=/Applications/SpektraLab.app
build_root="$(dirname -- "$repo")/SpektraLab-personal-build"
engine_only=false
sdk_override=""
base_tag=spektralab-v1.3.5
icon_source="$repo/modern_UI/Spektrafilm/PersonalIcon/AppIcon.png"

usage() {
  cat <<'USAGE'
Usage: Tools/build-personal.sh [--engine-only] [--template-app PATH] [--build-root PATH] [--sdk-path PATH] [--icon-png PATH]

Defaults:
  template: /Applications/SpektraLab.app, version 1.3.5 (20)
  output:   ../SpektraLab-personal-build/景到.app (beside the repo)
  icon:     modern_UI/Spektrafilm/PersonalIcon/AppIcon.png

Builds arm64/macOS 15+ with clang++ and swiftc, using unchanged release
resources plus one Personal.icns. --engine-only stops after compiling the C++ objects. Every run gets
a separate build directory; replacing a previous personal app retains a backup.
Without --sdk-path, probes installed SDKs for working SwiftUI @State support.
The official application is never changed, launched or closed.
USAGE
}

fail() { printf 'build-personal: %s\n' "$*" >&2; exit 1; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --engine-only) engine_only=true; shift ;;
    --template-app|--build-root|--sdk-path|--icon-png)
      [[ $# -ge 2 && -n "$2" ]] || fail "$1 requires a path"
      case "$1" in
        --template-app) template_app=$2 ;;
        --build-root) build_root=$2 ;;
        --sdk-path) sdk_override=$2 ;;
        --icon-png) icon_source=$2 ;;
      esac
      shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) fail "unknown option: $1" ;;
  esac
done

[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || fail 'Apple silicon macOS is required'
[[ -d "$template_app" ]] || fail "template app does not exist: $template_app"
template_app=$(CDPATH= cd -- "$template_app" && pwd -P)
template_info="$template_app/Contents/Info.plist"
[[ -f "$template_info" ]] || fail 'template Info.plist is missing'
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$template_info")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$template_info")
[[ "$version" == 1.3.5 && "$build" == 20 ]] || fail "need release 1.3.5 (20), found $version ($build)"
/usr/bin/codesign --verify --deep --strict "$template_app"

# A source-side shader edit cannot safely use a release's precompiled metallib.
# Likewise, retain the exact engine ABI and baked data that match those kernels.
# 景到 2026-11-05: the post-blur film cache is host-side C++ only (no kernel,
# ABI or baked-data change), so exactly these three files may differ; every
# other engine path -- shaders, include/, resources -- stays guarded.
guarded_paths=(engine "$app_sources/Canvas/Shaders.metal" "$app_sources/Resources"
  "$app_sources/Assets.xcassets" "$app_sources/SpektraLab.icon"
  ':(exclude)engine/src/pipeline/engine.cpp' ':(exclude)engine/src/pipeline/pipeline.cpp'
  ':(exclude)engine/src/pipeline/pipeline.hpp')
git -C "$repo" rev-parse --verify "$base_tag^{commit}" >/dev/null
git -C "$repo" diff --quiet "$base_tag" -- "${guarded_paths[@]}" ||
  fail 'engine (beyond the three allowed pipeline files), shaders or bundled resources differ from 1.3.5; use the full Xcode build'
[[ -z $(git -C "$repo" ls-files --others --exclude-standard -- "${guarded_paths[@]}") ]] ||
  fail 'untracked engine, shader or resource inputs require the full Xcode build'

resources="$template_app/Contents/Resources"
for file in default.metallib Assets.car SpektraLab.icns \
  Resources/engine/spektrafilm_constants.bin Resources/engine/spektrafilm.metallib \
  Resources/engine/neutral_print_filters.json Resources/engine/print_luts.json \
  Resources/Licenses/README.txt Resources/Licenses/SpektraLab-GPL-3.0.txt \
  Resources/Licenses/Profiles-and-LUTs-CC-BY-SA-4.0.txt \
  Resources/Licenses/Profiles-and-LUTs-CHANGELOG.txt Resources/Licenses/metal-cpp-Apache-2.0.txt; do
  [[ -s "$resources/$file" ]] || fail "missing template resource: $file"
done
[[ -d "$resources/Resources/engine/profiles" ]] || fail 'template profiles directory is missing'
[[ ! -e "$resources/Personal.icns" ]] || fail 'template already has Personal.icns; refusing to replace an official resource'
if ! $engine_only; then
  [[ -f "$icon_source" ]] || fail "personal icon PNG is missing: $icon_source"
  [[ -x "$here/build-personal-icon.sh" ]] || fail 'personal icon packaging tool is missing or not executable'
fi

sdk=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)
cxx=$(/usr/bin/xcrun --find clang++)
swiftc=$(/usr/bin/xcrun --find swiftc)
mkdir -p "$build_root"
build_root=$(CDPATH= cd -- "$build_root" && pwd -P)
output="$build_root/景到.app"
[[ "$output" != "$template_app" ]] || fail 'output must not replace the resource template'
run=$(mktemp -d "$build_root/build.XXXXXX")
mkdir -p "$run/objects" "$run/module-cache"
printf 'Build directory: %s\n' "$run"

# CLT can ship an SDK newer than its available SwiftUI compiler plugins. For
# example, macOS 27.2 imports @State as a SwiftUIMacros macro, but CLT 6.4.2
# lacks that plugin; its bundled 26.5 SDK retains the supported property wrapper.
# Probe the real SDK instead of rewriting application code to bypass @State.
cat > "$run/SwiftUIProbe.swift" <<'SWIFT'
import SwiftUI
struct SwiftUIProbe: View {
    @State private var value = false
    var body: some View { Button("Probe") { value.toggle() } }
}
SWIFT
sdk_candidates=("$sdk" "$(dirname -- "$sdk")"/MacOSX*.sdk)
if [[ -n "$sdk_override" ]]; then sdk_candidates=("$sdk_override"); fi
sdk=""
for candidate in "${sdk_candidates[@]}"; do
  [[ -d "$candidate" ]] || continue
  printf 'Probing SDK: %s\n' "$candidate" >> "$run/toolchain-probe.log"
  if "$swiftc" -swift-version 6 -target arm64-apple-macos15.0 -sdk "$candidate" \
    -module-cache-path "$run/module-cache" -typecheck "$run/SwiftUIProbe.swift" \
    >> "$run/toolchain-probe.log" 2>&1; then
    sdk=$candidate
    break
  fi
done
[[ -n "$sdk" ]] || fail "no installed SDK can compile SwiftUI; see $run/toolchain-probe.log"
printf 'Selected SDK: %s\n' "$sdk"

# Match gen-project.py's macOS source set, including future source additions.
# The Swift Windows/ directory contains macOS windows and must be included.
cpp_sources=()
while IFS= read -r -d '' source; do
  case "${source#"$repo/engine/src/"}" in
    io/*|desktop/*|gpu/vulkan_gpu.cpp|pipeline/windows_unported.cpp) continue ;;
  esac
  cpp_sources+=("$source")
done < <(find "$repo/engine/src" -type f -name '*.cpp' -print0 | LC_ALL=C sort -z)
[[ ${#cpp_sources[@]} -gt 0 ]] || fail 'no C++ sources found'
swift_sources=()
while IFS= read -r -d '' source; do
  swift_sources+=("$source")
done < <(find "$app_sources" -type f -name '*.swift' -print0 | LC_ALL=C sort -z)
[[ ${#swift_sources[@]} -gt 0 ]] || fail 'no Swift sources found'

{
  printf 'Base tag: %s\nSource commit: %s\n' "$base_tag" "$(git -C "$repo" rev-parse HEAD)"
  printf 'Template: %s\nTemplate version: %s (%s)\nSDK: %s\n' "$template_app" "$version" "$build" "$sdk"
  printf 'Target: arm64-apple-macos15.0\nBundle ID: com.mrfay.spektralab.personal\n'
  "$swiftc" --version
  "$cxx" --version
  git -C "$repo" status --short
} > "$run/provenance.txt"
git -C "$repo" diff --binary > "$run/source-changes.patch"
# Include untracked Swift additions in the source hash manifest as well.
shasum -a 256 "${swift_sources[@]}" "${cpp_sources[@]}" "$0" > "$run/source-sha256.txt"
if ! $engine_only; then
  shasum -a 256 "$icon_source" "$here/build-personal-icon.sh" >> "$run/source-sha256.txt"
fi
(
  cd "$resources"
  find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256
) > "$run/resources-sha256.txt"
if ! $engine_only; then
  # Validate/package the approved art before paying for a full compilation.
  "$here/build-personal-icon.sh" "$icon_source" "$run/Personal.icns" "$run"
  shasum -a 256 "$run/Personal.icns" > "$run/personal-icon-sha256.txt"
fi

cxxflags=(-std=c++20 -O2 -Wall -Wextra -target arm64-apple-macos15.0 -isysroot "$sdk"
  -I"$repo/engine/include" -I"$repo/engine/src" -I"$repo/engine/src/core"
  -I"$repo/engine/third_party/metal-cpp")
objects=()
for source in "${cpp_sources[@]}"; do
  relative=${source#"$repo/engine/src/"}
  object="$run/objects/${relative%.cpp}.o"
  mkdir -p "$(dirname -- "$object")"
  printf 'C++ %s\n' "$relative"
  "$cxx" "${cxxflags[@]}" -c "$source" -o "$object"
  objects+=("$object")
done
if $engine_only; then
  printf 'C++ compile passed: %s objects in %s\n' "${#objects[@]}" "$run/objects"
  exit 0
fi

staged="$run/景到.app"
mkdir -p "$staged/Contents/MacOS"
/usr/bin/ditto "$resources" "$staged/Contents/Resources"
cp "$template_info" "$staged/Contents/Info.plist"
if [[ -f "$template_app/Contents/PkgInfo" ]]; then
  cp "$template_app/Contents/PkgInfo" "$staged/Contents/PkgInfo"
fi
info="$staged/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string com.mrfay.spektralab.personal "$info"
/usr/bin/plutil -replace CFBundleName -string '景到' "$info"
/usr/bin/plutil -replace CFBundleDisplayName -string '景到' "$info"
/usr/bin/plutil -replace CFBundleExecutable -string SpektraLab "$info"
/usr/bin/plutil -replace CFBundleVersion -string 21.1 "$info"
/usr/bin/plutil -remove CFBundleIconName "$info" 2>/dev/null || true
/usr/bin/plutil -replace CFBundleIconFile -string Personal.icns "$info"
/usr/bin/plutil -replace PersonalBuild -bool YES "$info"
/usr/bin/plutil -replace PersonalBuildBaseTag -string "$base_tag" "$info"
# Do not claim that this CLT-built executable was built by the template's Xcode.
/usr/bin/plutil -remove DTXcode "$info" 2>/dev/null || true
/usr/bin/plutil -remove DTXcodeBuild "$info" 2>/dev/null || true
/usr/bin/plutil -replace DTSDKName -string "macosx$(/usr/bin/xcrun --sdk "$sdk" --show-sdk-version)" "$info"
/usr/bin/plutil -replace DTSDKBuild -string "$(/usr/bin/xcrun --sdk "$sdk" --show-sdk-build-version)" "$info"

printf 'Swift: compiling %s files and linking %s C++ objects\n' "${#swift_sources[@]}" "${#objects[@]}"
"$swiftc" -swift-version 6 -strict-concurrency=complete -O -whole-module-optimization \
  -module-name Spektrafilm -target arm64-apple-macos15.0 -sdk "$sdk" \
  -module-cache-path "$run/module-cache" \
  -import-objc-header "$app_sources/Service/Spektrafilm-Bridging-Header.h" \
  -I "$repo/engine/include" "${swift_sources[@]}" "${objects[@]}" \
  -lc++ -lsqlite3 -framework Metal -framework Foundation -framework QuartzCore \
  -framework CoreText -framework CoreGraphics -framework Accelerate \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$staged/Contents/MacOS/SpektraLab"

[[ -x "$staged/Contents/MacOS/SpektraLab" ]] || fail 'compiler produced no executable'
diff -rq "$resources" "$staged/Contents/Resources" > "$run/resource-copy-before-icon.txt" ||
  fail 'copied resources differ from the official release'
cp "$run/Personal.icns" "$staged/Contents/Resources/Personal.icns"
# Prove that every official resource remains untouched, and that there is just
# one addition. Do not exclude Assets.car or the original compiled icon.
if LC_ALL=C diff -rq "$resources" "$staged/Contents/Resources" > "$run/resource-copy-check.txt"; then
  fail 'the personal icon resource was not added'
else
  [[ $? -eq 1 ]] || fail 'could not compare the final resources'
fi
printf 'Only in %s: Personal.icns\n' "$staged/Contents/Resources" > "$run/expected-resource-addition.txt"
cmp -s "$run/expected-resource-addition.txt" "$run/resource-copy-check.txt" ||
  fail 'final resources changed beyond the single Personal.icns addition'
/usr/bin/codesign --force --sign - --options runtime \
  --entitlements "$app_sources/Spektrafilm.entitlements" "$staged"
/usr/bin/codesign --verify --deep --strict "$staged"
/usr/bin/plutil -lint "$info"

# Keep every previous successful personal build; never overwrite it in place.
if [[ -e "$output" || -L "$output" ]]; then
  backup=$(mktemp -d "$build_root/previous.XXXXXX")
  mv "$output" "$backup/"
  printf 'Previous personal app retained in: %s\n' "$backup"
fi
mv "$staged" "$output"
printf 'Personal application: %s\nProvenance and logs: %s\n' "$output" "$run"

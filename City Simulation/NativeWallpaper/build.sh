#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source "../NativeWallpaperSupport/build-support.sh"
package_name="$(printf '%s' "${PWD##*/}" | LC_ALL=C tr '[:upper:] -' '[:lower:]__')"
destination="${1:-$PWD/dist}"
scratch="${CITY_BUILD_DIR:-$PWD/.build/native-wallpaper}"
mkdir -p "$destination" "$scratch"
destination="$(cd "$destination" && pwd)"
scratch="$(cd "$scratch" && pwd)"
stage="$(mktemp -d "${TMPDIR:-/tmp}/city-wallpaper.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/City Simulation Wallpaper.app"
extension="$app/Contents/Extensions/CityWallpaper.appex"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" \
    "$extension/Contents/MacOS" "$extension/Contents/Resources"
cp NativeWallpaper/Carrier.plist "$app/Contents/Info.plist"
cp NativeWallpaper/Extension.plist "$extension/Contents/Info.plist"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$scratch/clang-modules}"

archs=(${CITY_NATIVE_ARCHS:-arm64 x86_64})
wallpaper_binaries=()
carrier_binaries=()
base_options=(--build-system native --manifest-cache local -c release)
if [ "${CITY_BUILD_UNNESTED:-0}" = 1 ]; then base_options+=(--disable-sandbox); fi
for arch in "${archs[@]}"; do
    triple="$arch-apple-macosx26.0"
    options=("${base_options[@]}" --scratch-path "$scratch/swiftpm-$arch" --triple "$triple")
    swift build "${options[@]}" --target CityArt
    bin="$(swift build "${options[@]}" --show-bin-path)"
    compile_bridge
    # Deleted sources can leave stale objects in SwiftPM's incremental cache.
    objects=()
    for target in CityEngine CityArt; do
        for source_file in Sources/"$target"/*.swift; do
            objects+=("$bin/$target.build/${source_file##*/}.o")
        done
    done
    link_wallpaper NativeWallpaper/ExtensionMain.swift "${objects[@]}" \
        -Xlinker -e -Xlinker _NSExtensionMain -o "$scratch/wallpaper-$arch"
    if [ "${CITY_BUILD_ABI_PROBE:-0}" = 1 ] && [ "$arch" = "$(uname -m)" ]; then
        link_wallpaper NativeWallpaper/Verify.swift "${objects[@]}" -o "$scratch/verify-wallpaper"
    fi
    compile_carrier
    wallpaper_binaries+=("$scratch/wallpaper-$arch")
    carrier_binaries+=("$scratch/carrier-$arch")
done

lipo -create "${wallpaper_binaries[@]}" -output "$extension/Contents/MacOS/CityWallpaper"
lipo -create "${carrier_binaries[@]}" -output "$app/Contents/MacOS/InstallWallpaper"
swift run "${base_options[@]}" --scratch-path "$scratch/preview" CityPreview \
    --png "$extension/Contents/Resources/city-thumbnail.png" 640 360
swift run "${base_options[@]}" --scratch-path "$scratch/preview" CityPreview --icns "$app/Contents/Resources/City.icns"
cp "$support/Protocol/LICENSE" "$extension/Contents/Resources/Aerial-LICENSE.txt"
sign_wallpaper "${CITY_SIGN_IDENTITY:--}"
ditto --norsrc "$app" "$destination/$(basename "$app")"
cp README.md DEVELOPMENT.md GALLERY.md ../LICENSE "$stage/"
ditto assets "$stage/assets"
ditto -c -k "$stage" "$destination/City Simulation Wallpaper.zip"

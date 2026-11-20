#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source "../NativeWallpaperSupport/build-support.sh"
package_name="$(printf '%s' "${PWD##*/}" | LC_ALL=C tr '[:upper:] -' '[:lower:]__')"
destination="${1:-$PWD/dist}"
scratch="${DESIGN_BUILD_DIR:-$PWD/.build/native-wallpaper}"
mkdir -p "$destination" "$scratch"
destination="$(cd "$destination" && pwd)"
scratch="$(cd "$scratch" && pwd)"
stage="$(mktemp -d "${TMPDIR:-/tmp}/design-wallpaper.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/System Design Wallpaper.app"
extension="$app/Contents/Extensions/DesignWallpaper.appex"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" \
    "$extension/Contents/MacOS" "$extension/Contents/Resources"
cp NativeWallpaper/Carrier.plist "$app/Contents/Info.plist"
cp NativeWallpaper/Extension.plist "$extension/Contents/Info.plist"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$scratch/clang-modules}"

archs=(${DESIGN_NATIVE_ARCHS:-arm64 x86_64})
wallpaper_binaries=()
carrier_binaries=()
base_options=(--build-system native --manifest-cache local -c release)
if [ "${DESIGN_BUILD_UNNESTED:-0}" = 1 ]; then base_options+=(--disable-sandbox); fi
for arch in "${archs[@]}"; do
    triple="$arch-apple-macosx26.0"
    options=("${base_options[@]}" --scratch-path "$scratch/swiftpm-$arch" --triple "$triple")
    swift build "${options[@]}" --target DesignArt
    bin="$(swift build "${options[@]}" --show-bin-path)"
    compile_bridge
    # Deleted sources can leave stale objects in SwiftPM's incremental cache.
    objects=()
    for target in DesignEngine DesignArt; do
        for source_file in Sources/"$target"/*.swift; do
            objects+=("$bin/$target.build/${source_file##*/}.o")
        done
    done
    objects+=("$bin/DesignEngine.build/resource_bundle_accessor.swift.o" "$bin"/WallpaperPalette.build/*.swift.o)
    link_wallpaper NativeWallpaper/ExtensionMain.swift "${objects[@]}" \
        -Xlinker -e -Xlinker _NSExtensionMain -o "$scratch/wallpaper-$arch"
    if [ "${DESIGN_BUILD_ABI_PROBE:-0}" = 1 ] && [ "$arch" = "$(uname -m)" ]; then
        link_wallpaper NativeWallpaper/Verify.swift "${objects[@]}" -o "$scratch/verify-wallpaper"
    fi
    compile_carrier
    wallpaper_binaries+=("$scratch/wallpaper-$arch")
    carrier_binaries+=("$scratch/carrier-$arch")
done

lipo -create "${wallpaper_binaries[@]}" -output "$extension/Contents/MacOS/DesignWallpaper"
lipo -create "${carrier_binaries[@]}" -output "$app/Contents/MacOS/InstallWallpaper"
swift run "${base_options[@]}" --scratch-path "$scratch/preview" DesignPreview \
    --png "$extension/Contents/Resources/design-thumbnail.png" 640 360 domestic-solar-power 22
iconset="$scratch/Design.iconset"
mkdir -p "$iconset"
swift run "${base_options[@]}" --scratch-path "$scratch/preview" DesignPreview --icon-png "$scratch/icon.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$scratch/icon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$scratch/icon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/Design.icns"
cp Sources/DesignEngine/Catalogue/*.json "$extension/Contents/Resources/"
cp "$support/Protocol/LICENSE" "$extension/Contents/Resources/Aerial-LICENSE.txt"
sign_wallpaper "${DESIGN_SIGN_IDENTITY:--}"
ditto --norsrc "$app" "$destination/$(basename "$app")"
cp README.md DEVELOPMENT.md ../LICENSE "$stage/"
ditto assets "$stage/assets"
ditto -c -k "$stage" "$destination/System Design Wallpaper.zip"

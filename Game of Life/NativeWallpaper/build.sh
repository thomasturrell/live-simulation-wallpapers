#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Match the compiler package name SwiftPM derives from the package directory.
package_name="$(printf '%s' "${PWD##*/}" | LC_ALL=C tr '[:upper:] -' '[:lower:]__')"
destination="${1:-$PWD/dist}"
mkdir -p "$destination"
destination="$(cd "$destination" && pwd)"
scratch="${LIFE_BUILD_DIR:-$PWD/.build/native-wallpaper}"
mkdir -p "$scratch"
scratch="$(cd "$scratch" && pwd)"
stage="$(mktemp -d "${TMPDIR:-/tmp}/life-wallpaper.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/Game of Life Wallpaper.app"
extension="$app/Contents/Extensions/LifeWallpaper.appex"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" \
    "$extension/Contents/MacOS" "$extension/Contents/Resources"
cp NativeWallpaper/Carrier.plist "$app/Contents/Info.plist"
cp NativeWallpaper/Extension.plist "$extension/Contents/Info.plist"
if [ -z "${CLANG_MODULE_CACHE_PATH:-}" ]; then
    export CLANG_MODULE_CACHE_PATH="$scratch/clang-modules"
fi
source "../NativeWallpaperSupport/build-support.sh"
archs=(${LIFE_NATIVE_ARCHS:-arm64 x86_64})
wallpaper_binaries=()
carrier_binaries=()
for arch in "${archs[@]}"; do
    triple="$arch-apple-macosx26.0"
    options=(--build-system native --manifest-cache local --scratch-path "$scratch/swiftpm-$arch" --triple "$triple" -c release)
    if [ "${LIFE_BUILD_UNNESTED:-0}" = 1 ]; then options+=(--disable-sandbox); fi
    swift build "${options[@]}" --target LifeArt
    bin="$(swift build "${options[@]}" --show-bin-path)"
    compile_bridge
    objects=("$bin"/WallpaperPalette.build/*.swift.o "$bin"/LifeEngine.build/*.swift.o "$bin"/LifeArt.build/*.swift.o)
    link_wallpaper NativeWallpaper/ExtensionMain.swift "${objects[@]}" \
        -Xlinker -e -Xlinker _NSExtensionMain -o "$scratch/wallpaper-$arch"
    if [ "${LIFE_BUILD_ABI_PROBE:-0}" = 1 ] && [ "$arch" = "$(uname -m)" ]; then
        link_wallpaper NativeWallpaper/Verify.swift "${objects[@]}" -o "$scratch/verify-wallpaper"
    fi
    compile_carrier
    wallpaper_binaries+=("$scratch/wallpaper-$arch")
    carrier_binaries+=("$scratch/carrier-$arch")
done
lipo -create "${wallpaper_binaries[@]}" -output "$extension/Contents/MacOS/LifeWallpaper"
lipo -create "${carrier_binaries[@]}" -output "$app/Contents/MacOS/InstallWallpaper"
CLANG_MODULE_CACHE_PATH="$scratch/icon-modules" xcrun swift Packaging/MakeIcon.swift "$app/Contents/Resources/Life.icns"
cp "$support/Protocol/LICENSE" "$extension/Contents/Resources/Aerial-LICENSE.txt"
cp NativeWallpaper/thumbnail.png "$extension/Contents/Resources/life-thumbnail.png"
sign_wallpaper "${LIFE_SIGN_IDENTITY:--}"
ditto --norsrc "$app" "$destination/$(basename "$app")"

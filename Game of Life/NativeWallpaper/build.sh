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
archs=(${LIFE_NATIVE_ARCHS:-arm64 x86_64})
wallpaper_binaries=()
carrier_binaries=()
for arch in "${archs[@]}"; do
    triple="$arch-apple-macosx26.0"
    options=(--build-system native --manifest-cache local --scratch-path "$scratch/swiftpm-$arch" --triple "$triple" -c release)
    if [ "${LIFE_BUILD_UNNESTED:-0}" = 1 ]; then options+=(--disable-sandbox); fi
    swift build "${options[@]}" --target LifeArt
    bin="$(swift build "${options[@]}" --show-bin-path)"
    xcrun clang -arch "$arch" -mmacosx-version-min=26.0 -fobjc-arc -c \
        NativeWallpaper/Protocol/WallpaperRuntime.m -o "$scratch/runtime-$arch.o"
    CLANG_MODULE_CACHE_PATH="$scratch/compiler-$arch" xcrun swiftc -target "$triple" -swift-version 5 -O -parse-as-library -package-name "$package_name" \
        -import-objc-header NativeWallpaper/Protocol/WallpaperBridge.h -I "$bin/Modules" \
        NativeWallpaper/{ExtensionMain,Presentation,WallpaperDriver,WallpaperXPCHandler}.swift \
        NativeWallpaper/Protocol/*.swift "$scratch/runtime-$arch.o" \
        "$bin"/LifeEngine.build/*.swift.o "$bin"/LifeArt.build/*.swift.o \
        -framework IOSurface -Xlinker -e -Xlinker _NSExtensionMain -o "$scratch/wallpaper-$arch"
    if [ "${LIFE_BUILD_ABI_PROBE:-0}" = 1 ] && [ "$arch" = "$(uname -m)" ]; then
        CLANG_MODULE_CACHE_PATH="$scratch/compiler-$arch" xcrun swiftc -target "$triple" -swift-version 5 -O \
            -parse-as-library -package-name "$package_name" \
            -import-objc-header NativeWallpaper/Protocol/WallpaperBridge.h -I "$bin/Modules" \
            NativeWallpaper/{Verify,Presentation,WallpaperDriver,WallpaperXPCHandler}.swift \
            NativeWallpaper/Protocol/*.swift "$scratch/runtime-$arch.o" \
            "$bin"/LifeEngine.build/*.swift.o "$bin"/LifeArt.build/*.swift.o \
            -framework IOSurface -o "$scratch/verify-wallpaper"
    fi
    CLANG_MODULE_CACHE_PATH="$scratch/compiler-$arch" xcrun swiftc -target "$triple" -O NativeWallpaper/Carrier.swift -o "$scratch/carrier-$arch"
    wallpaper_binaries+=("$scratch/wallpaper-$arch")
    carrier_binaries+=("$scratch/carrier-$arch")
done
lipo -create "${wallpaper_binaries[@]}" -output "$extension/Contents/MacOS/LifeWallpaper"
lipo -create "${carrier_binaries[@]}" -output "$app/Contents/MacOS/InstallWallpaper"
CLANG_MODULE_CACHE_PATH="$scratch/icon-modules" xcrun swift Packaging/MakeIcon.swift "$app/Contents/Resources/Life.icns"
cp NativeWallpaper/Protocol/LICENSE "$extension/Contents/Resources/Aerial-LICENSE.txt"
cp NativeWallpaper/thumbnail.png "$extension/Contents/Resources/life-thumbnail.png"
signing=(--force --sign "${LIFE_SIGN_IDENTITY:--}")
if [ "${LIFE_SIGN_IDENTITY:--}" != - ]; then signing+=(--options runtime --timestamp); fi
codesign "${signing[@]}" --entitlements NativeWallpaper/Sandbox.plist "$extension"
codesign "${signing[@]}" "$app"
codesign --verify --strict --deep --all-architectures "$app"
ditto --norsrc "$app" "$destination/$(basename "$app")"

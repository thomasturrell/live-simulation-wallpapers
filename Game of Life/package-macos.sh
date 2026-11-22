#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
destination="${1:-$PWD/dist}"
mkdir -p "$destination"
destination="$(cd "$destination" && pwd)"
scratch="${LIFE_BUILD_DIR:-$PWD/.build/package}"
mkdir -p "$scratch"
scratch="$(cd "$scratch" && pwd)"
stage="$(mktemp -d "${TMPDIR:-/tmp}/game-of-life.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/Game of Life.app"
saver="$stage/Game of Life.saver"

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" \
    "$saver/Contents/MacOS" "$saver/Contents/Resources"
cp Packaging/App.plist "$app/Contents/Info.plist"
cp Packaging/Saver.plist "$saver/Contents/Info.plist"

sdk="$(xcrun --sdk macosx --show-sdk-path)"
swiftlib="$(dirname "$(xcrun --find swiftc)")/../lib/swift/macosx"
for arch in arm64 x86_64; do
    triple="$arch-apple-macosx13.0"
    options=(--build-system native --manifest-cache local --scratch-path "$scratch/$arch" --triple "$triple" -c release)
    # Optional additional flags for constrained build environments.
    if [ "${LIFE_BUILD_UNNESTED:-0}" = 1 ]; then options+=(--disable-sandbox); fi
    swift build "${options[@]}"
    bin="$(swift build "${options[@]}" --show-bin-path)"
    cp "$bin/GameOfLife" "$scratch/app-$arch"
    xcrun clang -bundle -target "$triple" -isysroot "$sdk" \
        -L "$swiftlib" -L "$sdk/usr/lib/swift" -rpath /usr/lib/swift \
        "$bin"/WallpaperPalette.build/*.swift.o "$bin"/LifeEngine.build/*.swift.o "$bin"/LifeArt.build/*.swift.o "$bin"/LifeSaver.build/*.swift.o \
        -lswiftCompatibilityPacks -o "$scratch/saver-$arch"
done
lipo -create "$scratch/app-arm64" "$scratch/app-x86_64" -output "$app/Contents/MacOS/GameOfLife"
lipo -create "$scratch/saver-arm64" "$scratch/saver-x86_64" -output "$saver/Contents/MacOS/LifeSaver"

CLANG_MODULE_CACHE_PATH="$scratch/icon-modules" xcrun swift Packaging/MakeIcon.swift "$app/Contents/Resources/Life.icns"

for bundle in "$app" "$saver"; do
    plutil -lint "$bundle/Contents/Info.plist"
    signing=(--force --sign "${LIFE_SIGN_IDENTITY:--}")
    if [ "${LIFE_SIGN_IDENTITY:--}" != - ]; then signing+=(--options runtime --timestamp); fi
    codesign "${signing[@]}" "$bundle"
    codesign --verify --strict "$bundle"
    ditto --norsrc "$bundle" "$destination/$(basename "$bundle")"
done

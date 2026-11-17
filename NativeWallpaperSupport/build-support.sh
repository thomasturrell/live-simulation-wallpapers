# Sourced by each native wallpaper's build script.
support="../NativeWallpaperSupport"

compile_bridge() {
    xcrun clang -arch "$arch" -mmacosx-version-min=26.0 -fobjc-arc -c \
        "$support/Protocol/WallpaperRuntime.m" -o "$scratch/runtime-$arch.o"
}

link_wallpaper() {
    CLANG_MODULE_CACHE_PATH="$scratch/compiler-$arch" xcrun swiftc \
        -target "$triple" -swift-version 5 -O -parse-as-library -package-name "$package_name" \
        -import-objc-header "$support/Protocol/WallpaperBridge.h" -I "$bin/Modules" \
        NativeWallpaper/{WallpaperDriver,WallpaperChoice}.swift \
        "$support"/{Presentation,WallpaperXPCHandler}.swift "$support"/Protocol/*.swift \
        "$scratch/runtime-$arch.o" -framework IOSurface "$@"
}

compile_carrier() {
    CLANG_MODULE_CACHE_PATH="$scratch/compiler-$arch" xcrun swiftc -target "$triple" -O \
        "$support/Carrier.swift" -o "$scratch/carrier-$arch"
}

sign_wallpaper() {
    local identity="$1"
    local signing=(--force --sign "$identity")
    if [ "$identity" != - ]; then signing+=(--options runtime --timestamp); fi
    codesign "${signing[@]}" --entitlements "$support/Sandbox.plist" "$extension"
    codesign "${signing[@]}" "$app"
    codesign --verify --strict --deep --all-architectures "$app"
}

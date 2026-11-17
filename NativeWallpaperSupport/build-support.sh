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
    local entry="${1:-$support/CarrierMain.swift}"
    if [ "$#" -gt 0 ]; then shift; fi
    CLANG_MODULE_CACHE_PATH="$scratch/compiler-$arch" xcrun swiftc -target "$triple" -O -parse-as-library \
        -I "$bin/Modules" "$support/Carrier.swift" "$entry" "$@" -o "$scratch/carrier-$arch"
}

sign_wallpaper() {
    local identity="$1"
    local extension_entitlements="${2:-$support/Sandbox.plist}"
    local carrier_entitlements="${3:-}"
    local signing=(--force --sign "$identity")
    if [ "$identity" != - ]; then signing+=(--options runtime --timestamp); fi
    local carrier_signing=("${signing[@]}")
    if [ -n "$carrier_entitlements" ]; then carrier_signing+=(--entitlements "$carrier_entitlements"); fi
    codesign "${signing[@]}" --entitlements "$extension_entitlements" "$extension"
    codesign "${carrier_signing[@]}" "$app"
    codesign --verify --strict --deep --all-architectures "$app"
}

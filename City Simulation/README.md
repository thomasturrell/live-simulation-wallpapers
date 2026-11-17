# City Simulation

Watch an established isometric city grow. Cars commute between homes, shops, offices and factories, follow marked roads across three bridges, and queue at larger junctions. Buildings go up in stages and lights come on across the city at dusk. All of the pixel art is drawn by the renderer and covered by the repository’s MIT licence.

## Install on macOS

1. Build the wallpaper with the command below, or unzip a packaged build.
2. Move **City Simulation Wallpaper.app** into Applications and open it once. The app registers its wallpaper extension with PlugInKit. Click **Done** to quit the installer and leave the bundle in Applications.
3. Reopen System Settings. In **Wallpaper**, select **City Simulation** as the wallpaper. In **Wallpaper → Screen Saver → Custom**, select **City Simulation** as the screen saver. Repeat for each display or Space where you want it.
4. Start the screen saver or lock the Mac. The city animates on active saver surfaces. On return to the desktop, the extension brings the same scene to a stop over about three seconds when WallpaperAgent keeps the live surface visible.

The extension targets macOS 26 or later. The build script produces an ad-hoc signed universal app and ZIP by default. Set `CITY_SIGN_IDENTITY` to a Developer ID Application identity when building for distribution, then notarise the signed app. The carrier exits after registration. macOS hosts the animation and supplies the desktop image.

WallpaperAgent’s wallpaper extension interface is undocumented and may change with OS updates. Registration alone does not prove the extension will appear in both pickers. WallpaperAgent controls when it switches from a live layer to a cached image, so part or all of the slowdown may be hidden. If macOS withdraws the surface, City Simulation saves its current state and stops playback immediately. Per-display restore requires macOS to supply a display ID that maps to a Core Graphics display UUID. Requests without that identifier use session-only state.

## Build and preview

Use a Swift 6 toolchain with the macOS 26 SDK or newer. From this directory:

```sh
./NativeWallpaper/build.sh
./Packaging/test.sh
swift run -c release CityPreview
swift run -c release CityPreview --png /tmp/city-5k.png 5120 2880
swift run -c release CityPreview --png /tmp/city-at-night.png 1280 720 270
```

The first command produces the app and ZIP in `dist/`. Pass an output directory as the first argument to write them elsewhere, or set `CITY_NATIVE_ARCHS` to limit the architecture slices. The resizable preview window animates immediately without installing the extension. PNG export takes an optional width, height and time in simulated seconds. At the default seed, the first construction site opens after nine seconds and completes after fifteen.

For a probe of the native interfaces, build and run the probe from a graphical macOS login session:

```sh
CITY_BUILD_ABI_PROBE=1 ./NativeWallpaper/build.sh
state_dir="$(mktemp -d)"
.build/native-wallpaper/verify-wallpaper \
  "dist/City Simulation Wallpaper.app/Contents/Extensions/CityWallpaper.appex/Contents/Resources/city-thumbnail.png" \
  "$state_dir"
```

The probe exercises the real wallpaper settings and request types, remote Core Animation contexts, IOSurface snapshots, and the adapter’s playback, suspension, settling and persistence. Use `verify-wallpaper --local` with the same paths to exercise the settings, snapshots and lifecycle without allocating remote contexts. The probe runs outside WallpaperAgent. Before distributing, verify installed picker discovery, saver playback and lock/unlock from System Settings, display hot-plug and mirroring, Spaces, sleep and wake, and the idle energy profile on your target macOS versions.

## Implementation

- **CityEngine** owns a seedable 56 × 56 city and advances it at 30 fixed ticks per second. It routes trips on a connected road graph, balances development between housing and jobs, and enforces frontage and density limits. New road segments open frontage for future projects. Parks and riverbanks stay protected.
- **CityArt** draws original pixel art onto a virtual canvas. It caches terrain, buildings and their occlusion data, then adds traffic, water glints and chimney smoke. Playback samples the simulation up to 20 times per second. The desktop, snapshots and development preview use the same renderer and integer scaling.
- **NativeWallpaper** uses the same WallpaperAgent bridge as Game of Life. It atomically checkpoints each identified display to the extension’s Application Support directory about every 15 seconds of active simulation and at lifecycle transitions. A checkpoint includes the city clock, lots, current construction, vehicle trips and random state. Settings previews use disposable state. When the desktop settles, the timer stops and the final frame stays in place until the next session.

The private integration follows the [Game of Life native extension](../Game%20of%20Life/NativeWallpaper/INSTALL.md) and [Aerial’s wallpaper extension](https://github.com/AerialScreensaver/Aerial/tree/main/WallpaperExtension).

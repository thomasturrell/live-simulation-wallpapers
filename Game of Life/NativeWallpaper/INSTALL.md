# Game of Life Wallpaper 1.0.0

## Install

1. Quit the earlier Game of Life menu-bar app if it is running.
2. Move **Game of Life Wallpaper.app** to Applications and open it once. The app registers its embedded extension with PlugInKit. Click **Done** to exit it. Keep it in Applications so macOS can load its extension.
3. Reopen System Settings and choose **Game of Life** as the desktop wallpaper. Under **Wallpaper → Screen Saver → Custom**, choose **Game of Life** there too. If you have more than one display or Space, select it on each one or use **Show on all Spaces**.
4. Start the screen saver or lock the Mac. After unlock, allow a few seconds for the generation changes to slow and the desktop to settle.

Use the **Appearance** menu for Game of Life in Wallpaper settings. **Automatic** follows the Mac’s light or dark appearance. **Light** and **Dark** keep the chosen appearance as macOS switches modes.

In the **Colour** menu, **Spectrum** blends through six hues as the simulation runs, **Random** picks a hue for each simulation cycle, and **Accent** follows the macOS accent colour. Choose a named colour for a fixed hue or **Original** for the default palette.

This developer build is ad-hoc signed. The extension targets macOS 26 and later and contains Apple silicon and Intel slices. For distribution, use Developer ID signing and notarization. The wallpaper interface is undocumented and may change with macOS updates. If the choice is absent or renders incorrectly, select another wallpaper and use the separate **Wallpaper and Screen Saver** fallback ZIP. It includes the public `.saver` and still images. Its HEIC offers a scheduled Dynamic mode on macOS versions that recognise custom schedules. The fallback cannot animate through unlock.

## Integration

- Aerial's `com.apple.wallpaper` ExtensionKit target is the reference for the `Contents/Extensions` bundle, WallpaperAgent XPC protocol, remote Core Animation context, IOSurface snapshots, and the settings model that exposes one choice in both pickers.
- AppexSaverMinimal uses `com.apple.screensaver` and `Contents/PlugIns`. Its registration and lifecycle notes explain why Settings and the real saver can have separate instances, why display geometry arrives after view creation, and why a stop callback is insufficient to save state. A `com.apple.screensaver` extension alone does not provide the same drawable desktop surface.
- The extension executable starts through Foundation’s `NSExtensionMain` and retains the Swift `@main` metadata that ExtensionFoundation uses to load the provider.
- The carrier app registers its embedded extension using `pluginkit -a`, shows a setup window, and exits. The build does not modify WallpaperAgent's preferences. WallpaperAgent creates and owns the remote surfaces. The adapter uses its request lifecycle, plus the saver start, stop, and unlock notifications observed by Aerial. The actual visibility and length of the unlock animation depend on when WallpaperAgent switches from the live surface to its cached image.
- Each display has an independent world, keyed by the display's Core Graphics UUID, and one or more correctly scaled remote views. Saver and desktop views for the same display share that world. Previews use disposable worlds. The extension saves a compact atomic checkpoint after each generation in its own container. It includes living cells, generation number, elapsed time since pattern injection, random generator state, and palette phase. The final checkpoint is used after a restart.
- While presenting on the Lock Screen or as the saver, the extension advances about once a second. On exit, it runs a short sequence with increasing intervals and longer fades, then cancels the timer. A sleeping or released display has no timer. Stationary snapshots are rendered on demand.
- The private bridge checks the expected classes, wrapper layouts, and context creation before returning a surface. The snapshot encoding adapter is scoped to the extension process. No network, global file access, or library-validation exceptions are requested.

## Build and verify

Run `NativeWallpaper/build.sh` from the source directory using a macOS 26 or newer SDK. Set `LIFE_SIGN_IDENTITY` for distribution. The supported `.saver` can still be built with `./package-macos.sh`.

Run `./Packaging/test.sh` for simulation tests. To build the local ABI probe, set `LIFE_BUILD_ABI_PROBE=1` when packaging. Run the resulting `verify-wallpaper` from the build directory with the path to `NativeWallpaper/thumbnail.png` and an empty writable directory for probe checkpoints. It exercises real platform classes, remote contexts and IOSurfaces, plus the rendering and playback lifecycle. This is separate from selecting the extension and doing a full lock/unlock test in System Settings.

## References

- [Aerial wallpaper extension source](https://github.com/AerialScreensaver/Aerial/tree/main/WallpaperExtension)
- [AppexSaverMinimal sample](https://github.com/AerialScreensaver/AppexSaverMinimal)
- [Aerial lifecycle notes](https://aerialscreensaver.github.io/developers/appex-lifecycle/)
- [Aerial registration and distribution notes](https://aerialscreensaver.github.io/developers/appex-distribution/)

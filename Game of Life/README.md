# Game of Life

A native macOS wallpaper app and idle screen saver based on Conway’s Game of Life. Every frame is drawn from the simulation. The **Colour** menu offers the original graphite and warm-white palette, eight fixed colours, Spectrum, Random and the macOS accent colour.

## Native WallpaperAgent extension

**Game of Life Wallpaper 2.0.3** embeds an ExtensionKit wallpaper and screen saver for macOS 26 or later. It persists the Conway world and colour phase per display, animates during saver playback, then settles the desktop and stops its timers. The carrier app can close after installation.

[Installation, compatibility and build notes](NativeWallpaper/INSTALL.md)

## Dynamic Desktop fallback

Use the **Wallpaper and Screen Saver** ZIP for a setup that runs entirely through System Settings. Import `Game of Life.heic` under **Wallpaper → Your Photos → Add Photo → Choose File**, then select **Dynamic** if macOS offers it. The file contains eight 5120 × 3200 generations scheduled across local time, with separate light and dark stills. The live Conway screen saver is configured separately in System Settings. [Wallpaper setup](Packaging/Wallpaper-Setup.txt)

Apple documents importing images and configuring its own Dynamic Wallpapers. The custom HEIC uses the time-of-day metadata described by the [wallpapper project](https://github.com/mczachurski/wallpapper). Its mode picker can vary by macOS version. The saver and wallpaper are hosted separately, so the desktop does not play the saver’s final seconds after unlocking. [Apple's Wallpaper guide](https://support.apple.com/guide/mac-help/choose-your-desktop-picture-mchlp3013/mac)

## Optional desktop app

Use the app ZIP or run `./package-macos.sh` in this directory. Open the resulting `Game of Life.app` from Finder and use its grid-shaped menu-bar icon to reopen settings. Open `Game of Life.saver` to install the optional screen saver, then select it in System Settings. [Setup.txt](Setup.txt) has the current and earlier macOS menu paths.

The binaries target macOS 13 or later and include Apple silicon and Intel slices. The local package is ad-hoc signed. For distribution, supply a Developer ID Application identity in `LIFE_SIGN_IDENTITY`, then notarise the bundles.

### Desktop and screen saver

- **Add Logo** puts optional branding in the bottom right of the desktop and its still exports. Import a self-contained SVG with outlined lettering or a transparent PNG. For a second version, use the same crop and proportions. The wallpaper selects the artwork that contrasts better with its current colour. Use **Remove** on the primary logo to clear both versions.
- The menu-bar app copies logos into `~/Library/Application Support/Game of Life/Branding`. The standalone screen saver also offers logo import in its options, using the Application Support directory available to its macOS host.
- **Settle on Return** runs a few increasingly spaced generations when the desktop comes back into view, then stops the timer. **Continuous** is available in the same Desktop motion menu. Both use a mouse-transparent window beneath Finder icons on each display while the app is open. Spaces and desktop modes can affect when AppKit reports the window as visible.
- **Set Still Wallpaper** saves a Retina-size PNG for each connected display and applies it with `NSWorkspace`. The PNGs live in the app’s Application Support folder so macOS can continue to load them after the app quits. An applied still keeps its captured colours. Set it again after changing appearance if you want a new still.
- **Lock Screen motion** comes from the selected screen saver. Apple’s Lock Screen command can start it on supported macOS versions, and a Start Screen Saver hot corner starts it directly. Use Screen Saver Options to match the desktop settings if macOS isolates the host preferences.
- **Transition** uses public AppKit visibility and wake events. The screen saver also signals the desktop app when its view ends via the public distributed notification centre, with visibility still governing desktop playback. The two surfaces run independent worlds, so the desktop settles its own generation rather than taking over Apple’s native Lock Screen playback.

[Apple’s desktop image API](https://developer.apple.com/documentation/appkit/nsworkspace/setdesktopimageurl(_:for:options:)) · [Apple’s Screen Saver framework](https://developer.apple.com/documentation/ScreenSaver) · [Using a screen saver on macOS](https://support.apple.com/en-euro/guide/mac-help/mchl4b68853d/27/mac/27)

## Development

Open `Package.swift` in Xcode, or build with a recent macOS SDK and Swift 6 toolchain:

```sh
swift build
./Packaging/test.sh
./package-macos.sh
xcrun swift Packaging/verify-saver.swift "dist/Game of Life.saver"
swift run -c release GameOfLife --export-wallpaper dist
```

- `LifeEngine` implements B3/S23 on a torus with two reusable buffers. It seeds each scene with gliders, oscillators, stable structures, spaceships and small colonies. Optional injection introduces known patterns into quiet areas.
- `LifeArt` calculates the overscan and batches cell shapes by colour. A generation timer advances the world independently of Core Animation, which interpolates the births and deaths. Stable cells keep their tone. There is no application-driven frame loop or Metal dependency.
- `LifeApp` provides native settings and one live surface per display, refreshing when displays change. The view stops its generation timer when paused, detached, hidden, occluded, or notified of sleep or an inactive session.
- `LifeSaver` delegates drawing to the same view and suspends it when the host stops animation or removes the view from the window.

Tests cover all live/dead neighbour combinations, stable structures, a wraparound oscillator, glider travel, agreement with a reference implementation, overscan on landscape/portrait/ultrawide geometries, 2× snapshots, preference persistence, independence from rendering frequency, and desktop deceleration, freeze, reveal, and pause. The bundle test mounts two differently sized saver views and checks generation changes after start, stop, detachment and resume.

Before distribution, verify Finder stacking and click-through, display hot-plug and mirroring, Spaces and Stage Manager, idle activation and wake, host preferences, and energy use on a Mac with connected displays. The test host exercises the bundle and its view lifecycle independently of System Settings.

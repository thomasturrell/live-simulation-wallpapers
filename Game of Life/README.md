# Game of Life

A native macOS wallpaper app and idle screen saver based on Conway’s Game of Life. Every frame is drawn from the simulation. The **Colour** menu offers the original graphite and warm-white palette, eight fixed colours, Spectrum, Random and the macOS accent colour.

## Native WallpaperAgent extension

**Game of Life Wallpaper 1.0.0** embeds an ExtensionKit wallpaper and screen saver for macOS 26 or later. It persists the Conway world and colour phase per display, animates during saver playback, then settles the desktop and stops its timers. The carrier app can close after installation.

[Download from GitHub Releases](https://github.com/thomasturrell/live-simulation-wallpapers/releases), then follow the [installation, compatibility and native build notes](NativeWallpaper/INSTALL.md).

## Alternatives for macOS 13 or later

The optional menu-bar desktop app, standalone screen saver and scheduled HEIC wallpaper can be built from source:

- [Desktop app and screen saver setup](Setup.txt) covers building, installation, motion controls and Lock Screen behaviour.
- [Dynamic Desktop setup](Packaging/Wallpaper-Setup.txt) covers exporting and importing the scheduled HEIC wallpaper and its light and dark PNG alternatives.

The custom HEIC uses the time-of-day metadata described by the [wallpapper project](https://github.com/mczachurski/wallpapper). Its mode picker can vary by macOS version. See [Apple's Wallpaper guide](https://support.apple.com/guide/mac-help/choose-your-desktop-picture-mchlp3013/mac) for importing images and configuring Apple's Dynamic Wallpapers.

The local package includes Apple silicon and Intel slices and is ad-hoc signed. For distribution, supply a Developer ID Application identity in `LIFE_SIGN_IDENTITY`, then notarise the bundles.

### Desktop and screen saver

- **Set Still Wallpaper** saves a Retina-size PNG for each connected display and applies it with `NSWorkspace`. The PNGs live in the app’s Application Support folder so macOS can continue to load them after the app quits. An applied still keeps its captured colours. Set it again after changing appearance if you want a new still.
- **Transition** uses public AppKit visibility and wake events. The screen saver also signals the desktop app when its view ends via the public distributed notification centre, with visibility still governing desktop playback. The desktop settles its own generation on return. Its live window is mouse-transparent and sits beneath Finder icons on each display.

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

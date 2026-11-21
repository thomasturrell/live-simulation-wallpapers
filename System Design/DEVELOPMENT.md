# Developing System Design

For downloads, wallpaper options and installation, see the [System Design README](README.md).

## Build and preview

Use a Swift 6 toolchain and the macOS 26 SDK or later. Run these commands from the `System Design/` directory in a source checkout.

```sh
./Packaging/test.sh
./NativeWallpaper/build.sh
swift run DesignPreview
```

The test wrapper runs the Swift Testing suite. The native build writes the app and ZIP to `dist/`. By default it builds for Apple silicon and Intel. Pass an output directory as the first argument to write them elsewhere. The ZIP includes the app, both guides, the gallery images and the licence.

The preview opens an animated window without installing the wallpaper. Use **System** to pick a diagram by subject, or choose **Entire catalogue** to explore automatically. **Palette** recolours the diagram as it plays. Tick **Show system label** to display the caption. The preview keeps its own temporary state.

To export a repeatable frame, pass `--png` followed by the output path, width and height. The optional arguments, in order, are the system or category ID, elapsed playback time in seconds, colour and appearance. Append `--show-system-label` to include the caption.

```sh
swift run DesignPreview --png /tmp/solar.png 1600 1000 domestic-solar-power 12 green
swift run DesignPreview --png /tmp/water-cycle.png 1600 1000 water-cycle 20 blue Dark --show-system-label
```

## Catalogue and playback

The four JSON files in `Sources/DesignEngine/Catalogue/` supply the wallpaper picker and the artwork. Each system has a stable ID, name, description, category and layout. Layouts include horizontal and vertical flows, hierarchies, clusters, rings, hubs and meshes.

Each node has a local ID, name and kind. Use the optional `detail` field for a description, `symbol` for a built-in macOS symbol and `group` for subsystem membership. Groups can name a parent. Each directed edge gives its source, target, relationship kind and a verb phrase for its label. Add an edge in each direction to describe a two-way exchange.

Use the same `concept` key on two nodes when a viewer can follow the connection between systems. For example, **Battery bank** and **Cell stack** both use `storage`. During a transition, that card stays in place while the diagram around it changes.

`DesignEngine` validates references, group ancestry and connectedness when it loads the catalogue. A seed determines the order in which connected components appear. Recent visits help the engine choose a fresh system. Each display’s versioned checkpoint records the selection, entry component, seed, recent visits and position within the current action, so it can resume partway through a transition.

`DesignArt` measures and routes a sheet once, then updates its Core Animation layers. The interactive preview, PNG exporter, native wallpaper and desktop snapshots all use that renderer. The local `WallpaperPalette` target in Game of Life supplies the colour calculations. The native adapter uses the collection’s shared WallpaperAgent bridge.

## Verify on a Mac

1. Select **System Design** for both the wallpaper and screen saver. Try **Domestic solar power**, change the palette and toggle the labels. Check that its two opening cards and their connecting arrow are readable.
2. Lock for five seconds, then unlock. Watch the cards ease down and their shadows shorten, even between reveals. Lock again for about a minute. Look for another component appearing and a pulse following an arrow. Choose **Entire catalogue** to see a transition between systems.
3. Unlock during a reveal or dissolve. The action should finish and the desktop should come to rest within about three seconds. Lock again to check that playback resumes from that point. Use Activity Monitor or Instruments to check idle CPU use after settling.
4. Try a second display or Space, switch the Mac’s appearance and open and close Settings previews. Check that each identifiable display resumes independently and that previews leave its history intact.

macOS controls the wallpaper surfaces. If it replaces a live surface, the next live desktop surface resumes the unfinished settle. Desktop snapshots can show the motion as it settles. Once macOS suspends the live surface, its snapshot shows the resting position. The extension saves on unlock, on suspension and periodically during playback. A display without a stable identifier keeps its state for the current session.

The WallpaperAgent interface is private and can change with macOS updates. Run the following probe to exercise the native picker models, snapshots and timer lifecycle without registering the app.

```sh
DESIGN_BUILD_ABI_PROBE=1 DESIGN_NATIVE_ARCHS="$(uname -m)" ./NativeWallpaper/build.sh
.build/native-wallpaper/verify-wallpaper --local \
  "dist/System Design Wallpaper.app/Contents/Extensions/DesignWallpaper.appex/Contents/Resources/design-thumbnail.png" \
  "$(mktemp -d)"
```

Omit `--local` in a graphical login session to exercise remote Core Animation context creation too.

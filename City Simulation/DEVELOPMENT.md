# Developing City Simulation

Build, preview and integration reference for contributors. For downloads, features and installation, see the [City Simulation README](README.md).

## Build and preview

Use a Swift 6 toolchain with the macOS 26 SDK or newer. From this directory:

```sh
./NativeWallpaper/build.sh
./Packaging/test.sh
swift run -c release CityPreview
swift run -c release CityPreview --png /tmp/city-5k.png 5120 2880
swift run -c release CityPreview --png /tmp/city-at-night.png 1280 720 270
swift run -c release CityPreview --seed 215 --png /tmp/city-airport.png 1280 720 750
```

The first command produces the app and ZIP in `dist/`. Pass an output directory as the first argument to write them elsewhere, or set `CITY_NATIVE_ARCHS` to limit the architecture slices. The resizable preview window animates immediately without installing the extension. PNG export takes an optional width, height and time in simulated seconds. At the default seed, the first construction site opens after nine seconds and completes after fifteen.

Use `./Packaging/test.sh` rather than bare `swift test`: the wrapper disables XCTest and loads the Swift Testing macro plug-in when needed. For the host-only native build used by CI, run `CITY_NATIVE_ARCHS="$(uname -m)" ./NativeWallpaper/build.sh`. Keep generated `.build/` and `dist/` output untracked.

## Native integration and distribution

The installer app registers its embedded `CityWallpaper.appex` with PlugInKit and exits after **Done**. macOS hosts the animation and supplies the desktop image. The release ZIP contains `City Simulation Wallpaper.app`, `README.md`, `DEVELOPMENT.md`, `GALLERY.md`, `LICENSE` and the `assets/` gallery images.

The extension targets macOS 26 or later. The build script produces an ad-hoc signed universal app and ZIP by default. Set `CITY_SIGN_IDENTITY` to a Developer ID Application identity when building for distribution, then notarise the signed app.

Keep a single installed copy of the app and open that copy to register it. After replacing a build, quit/reopen System Settings so its cached menu refreshes. macOS can retain an already-running extension; restarting the wallpaper host loads the replacement binary. City checkpoints are stored separately in the extension's Application Support directory.

On return to the desktop, playback settles to a stop over four seconds when WallpaperAgent keeps the live surface visible. WallpaperAgent’s wallpaper extension interface is undocumented and may change with OS updates. Registration alone does not prove the extension will appear in both pickers. WallpaperAgent controls when it switches from a live layer to a cached image, so part or all of the slowdown may be hidden. If macOS withdraws the surface, City Simulation saves its current state and stops playback immediately. Per-display generation and restore require macOS to supply a display ID that maps to a Core Graphics display UUID. Previews and requests without that identifier use the default city and session-only state.

### Native interface verification

For a probe of the native interfaces, build and run the probe from a graphical macOS login session:

```sh
CITY_BUILD_ABI_PROBE=1 ./NativeWallpaper/build.sh
state_dir="$(mktemp -d)"
.build/native-wallpaper/verify-wallpaper \
  "dist/City Simulation Wallpaper.app/Contents/Extensions/CityWallpaper.appex/Contents/Resources/city-thumbnail.png" \
  "$state_dir"
```

The probe exercises the real wallpaper settings and request types, remote Core Animation contexts, IOSurface snapshots, and the adapter’s playback, suspension, settling and persistence. Use `verify-wallpaper --local` with the same paths to exercise the settings, snapshots and lifecycle without allocating remote contexts. The probe runs outside WallpaperAgent. Before distributing, verify installed picker discovery, saver playback and lock/unlock from System Settings, display hot-plug and mirroring, Spaces, sleep and wake, and the idle energy profile on your target macOS versions.

## City model and aviation

Each display starts with its own river, bridges and street grids, generated from its display UUID. Cars commute between homes, shops, offices and factories, and queue at larger junctions. Buildings go up in stages and lights come on across the city at dusk. All of the pixel art is drawn by the renderer and covered by the repository’s MIT licence.

Generated cities have a 25% chance of reserving a 12 × 6 lot airport site on the outskirts when suitable land is available. The public forecourt and car park reuse an existing street where possible. A straight spur can extend access by up to two lots. Placement checks that the surviving streets stay connected and trims any one-tile stubs left at nearby junctions. Rivers, bridges, parks, promenades and low approach corridors stay protected. The fixed default preview city includes an airport.

The airfield starts with a grass runway, a flying clubhouse, a windsock and a hangar. It gains a paved runway, a glazed terminal and a control tower as a local airport. The mature regional layout adds a second boarding stand, taller folded roofs and a maintenance yard. The two upgrades use the city's construction schedule after a flight has completed at each stage. New arrivals wait until the work finishes. The fixed footprint and access street serve all three stages.

Light aircraft visit the grass airfield, turboprops visit the local airport, and turboprops and regional jets use the mature apron. One airport flight operates at a time, with longer quiet intervals at night. Passenger cars use the forecourt in both directions. During a stop at the gate, a baggage tug briefly moves around the maintenance yard. Independent overflights occasionally cross the wider city. All activity uses the existing simulation clock and renderer.

## Environment and configuration

The **Environment** menu in System Settings → Wallpaper (or Screen Saver) has three choices:

- **Simulation World** (default) uses the city's own eight-minute day/night cycle. Spring, summer, autumn and winter each last two days: eight days and **64 minutes of active city playback** make a year. The saved city clock drives the calendar and weather. Suspension, restart and the existing four-second settle-to-still behaviour preserve the same timeline as traffic and construction; inactive time is never caught up.
- **Real World · Northern Hemisphere** follows macOS Light/Dark appearance for lighting, independently of actual sunrise/sunset. Seasonal appearance follows the Mac's local Gregorian calendar, smoothly interpolating twelve first-of-month reference stages with actual month lengths and leap years. Rendering after time away immediately uses the current date.
- **Real World · Southern Hemisphere** uses the same system appearance and calendar, with the seasonal artwork shifted by six months.

Real World modes use **neutral, dry conditions** in every season. They do not generate fictional weather, make network requests, request location permission or require credentials. Apple WeatherKit integration is deferred. There are no provider, location, geography or development preview controls in Wallpaper settings.

Both calendars share the same pixel artwork: deciduous trunks and branches with growing/withdrawing leaf clusters, varied autumn colours and selected blossom trees; evergreen spruces retain layered needles. Lawns, flowers, park gardens and fallen leaves transition with the seasons. Stable per-tree phase and shape variation prevent synchronised foliage changes. Winter alone does not paint snow on the city.

### Simulated weather

The percentage table in [SimulatedWeather.swift](Sources/CityEngine/SimulatedWeather.swift) controls new weather spells and is intentionally kept out of Wallpaper settings:

| Season | Clear | Cloudy | Rain | Snow |
| --- | ---: | ---: | ---: | ---: |
| Spring | 40% | 30% | 30% | 0% |
| Summer | 60% | 25% | 15% | 0% |
| Autumn | 25% | 30% | 40% | 5% |
| Winter | 20% | 25% | 20% | 35% |

Every row totals 100%. Each spell samples the current fictional season's probabilities. Summer cannot select snow, autumn is rainier than summer, and winter can still be clear, cloudy or rainy. Wind uses a separate deterministic random stream and can accompany any of the four conditions.

Spells last 2½ minutes of city time, with 24-second smooth transitions followed by stable conditions. Repeated selections can naturally produce longer spells. Snow cover thaws over the following spell after the flakes stop. Weather is computed from the checkpointed city tick and an independent seed, so it resumes exactly across freezes and restarts without using the traffic/development random stream. No separate weather cache, timer or background process is needed.

Existing weather art remains shared: rain darkens roads and vegetation, adds puddles/ripples and restrained slanted rain; snow adds drifting flakes and temporary cover on lawns, trees and building/airport roofs. Cloud shadows and wind-blown leaves/seeds stay subtle. None of these effects edits terrain, buildings, construction or routes.

### CityPreview controls and exports

The standalone development preview has the same Environment choices plus a fractional-month slider, previous/next stage controls, live/day/night lighting, clear/cloudy/rain/snow overrides, independent wind inspection and pause. It uses disposable city state and never changes the installed wallpaper's settings or checkpoints.

Choose **New seed** to start a randomly generated city, or enter a decimal seed and choose **Load seed** to revisit a layout. The preview starts each new city at the beginning and retains your environment controls and pause setting. Pass `--seed` to start the live preview or make a PNG or gallery export with the same layout. Seed 215 shows the full airport at the default preview size.

```sh
swift run -c release CityPreview --seed 215
swift run -c release CityPreview --environment northern --month 10.5 --light day --weather rain --wind 0.7
swift run -c release CityPreview --png /tmp/winter-snow.png 1280 720 \
  --environment simulation --month 4 --light night --weather snow --wind 0.3
swift run -c release CityPreview --environment southern --month 1 --light day
swift run -c release CityPreview --gallery /tmp/city-environment-gallery
```

`--month` is one-based and fractional: the real calendars use 1=January through 12=December (13 wraps to January); Simulation World uses 1=spring, 2=summer, 3=autumn, 4=winter (5 wraps to spring). `--wind` accepts 0...1 and is independent of the weather override. Export and gallery commands use the production renderer without changing the system clock or writing saved cities. The gallery contains monthly, fictional-year, hemisphere, weather/wind and vegetation sheets.

### Environmental verification

`./Packaging/test.sh` covers the three Environment options; real and fictional calendars; leap years and local time zones; month/year continuity; Northern/Southern seasonal reversal; appearance-driven lighting and neutral, dry Real World weather; exact seasonal percentage distributions and zero-probability outcomes; spell duration, smooth transitions, independent wind and snow thaw; checkpoint replay, suspension, settling and restart; preview overrides, seasonal tree silhouettes, weather rendering/cache invalidation and small-canvas clipping. It also runs the existing traffic, development, construction, aviation and layout tests. Tests use no network services.

Build with `CITY_BUILD_ABI_PROBE=1 ./NativeWallpaper/build.sh`, then run the probe in [Native interface verification](#native-interface-verification). It checks one Environment picker with exactly three items against the real native XPC types, default and updated values, system-appearance lighting, dry Real World snapshots, zero idle playback timers, suspension and checkpoint resume. It also sends a download-status request through Apple's native XPC interface to catch reply-type mismatches that disconnect WallpaperAgent during environment changes. Repeated unchanged host/appearance updates and Settings preview surfaces must not cause snapshot refresh loops. Installed WallpaperAgent behaviour still needs the manual macOS checks listed above because its private host interface can change independently of the renderer.

## Architecture and persistence

- **CityEngine** owns a seedable 56 × 56 city and advances it at 30 fixed ticks per second. It routes trips on a connected road graph, balances development between housing and jobs, and enforces frontage and density limits. New road segments open frontage for future projects. Parks and riverbanks stay protected.
- **CityArt** draws original pixel art onto a virtual canvas. It caches terrain, airport facilities, buildings and their occlusion data, then adds road traffic, aircraft, water glints and chimney smoke. Playback samples the simulation up to 20 times per second. The desktop, snapshots and development preview use the same renderer and integer scaling.
- **NativeWallpaper** atomically checkpoints each identified display to the extension's Application Support directory about every 15 seconds of active simulation and at lifecycle transitions. A checkpoint includes the city clock, lots, construction, vehicle trips, airport development and flight schedules, city random state and an independent environmental seed. Format-5 saves from before airport development retain their street graph and resume with a mature airport. System Settings preview surfaces use disposable city state. Settling stops the timer and retains the final frame. Environmental cache keys include the hemisphere-adjusted seasonal phase, lighting and weather, so changes redraw correctly even at the same city tick. Quantized palettes retain the terrain/building cache for most frames.

The private integration follows the [Game of Life native extension](../Game%20of%20Life/NativeWallpaper/INSTALL.md) and [Aerial’s wallpaper extension](https://github.com/AerialScreensaver/Aerial/tree/main/WallpaperExtension).

The Swift package defines `CityEngine`, `CityArt`, `CityPreview` and `CityTests`. The native adapter is built separately by `NativeWallpaper/build.sh`, using the shared [`NativeWallpaperSupport`](../NativeWallpaperSupport/) bridge and build helpers.

## Asset reference

See the [City Simulation gallery](GALLERY.md) for city views, environment sheets and the full artwork catalogue. Generate the environment sheets with the `CityPreview --gallery` command in [CityPreview controls and exports](#citypreview-controls-and-exports).

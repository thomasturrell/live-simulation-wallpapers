# Repository instructions

## Architecture and code

- Two independent Swift packages live in `Game of Life/` and `City Simulation/`; there is no root package. Their `Package.swift` files define targets and deployment versions. Native extensions require macOS 26; the optional Game of Life app and `.saver` target macOS 13.
- Keep simulation logic in `LifeEngine` / `CityEngine`, rendering in `LifeArt` / `CityArt`, and host behaviour in `LifeApp`, `LifeSaver`, `CityPreview` or each `NativeWallpaper/` adapter. Native extensions are built by shell scripts using shared `NativeWallpaperSupport/`, outside the SwiftPM target graph.
- Follow nearby Swift style: four-space indentation, UpperCamelCase types, lowerCamelCase members, and narrow access (`private`, internal or `package` where appropriate). Keep AppKit view and wallpaper-driver work on the main actor.
- Preserve simulation evolution independently of drawing frequency, seeded reproducibility and checkpoint restore/migration behaviour. Native playback is per display; previews use disposable state, and suspended or settled playback stops its timers.

## Build and validation

Use a Swift 6 toolchain and macOS 26 SDK or newer for native builds. From the repository root, the CI checks are:

```sh
"Game of Life/Packaging/test.sh"
"City Simulation/Packaging/test.sh"
LIFE_NATIVE_ARCHS="$(uname -m)" "Game of Life/NativeWallpaper/build.sh"
CITY_NATIVE_ARCHS="$(uname -m)" "City Simulation/NativeWallpaper/build.sh"
git diff --check
```

- Use the test wrappers rather than bare `swift test`: they disable XCTest and load the Swift Testing macro plug-in when needed. Extend the existing `Tests/` suites for changed simulation, rendering, persistence or playback behaviour. Tests use `Testing`, `@Test`, `#expect` and `#require`; AppKit lifecycle tests use `@MainActor`.
- Run the affected package's tests and native build for code changes; changes to shared native support require both builds and suites. Default native builds produce universal arm64/x86_64 bundles; the commands above match CI's host-only builds. Keep generated `.build/` and `dist/` output untracked.
- Follow the package READMEs for preview, export and fallback commands. For native bridge changes, use the ABI probes described in [Game of Life's installation notes](Game%20of%20Life/NativeWallpaper/INSTALL.md#build-and-verify) and [City Simulation's build notes](City%20Simulation/README.md#build-and-preview). Builds and probes do not replace installed picker, lock/unlock, display and energy checks on a Mac.
- Treat [.github/workflows/ci.yml](.github/workflows/ci.yml), the packaging scripts and `NativeWallpaperSupport/build-support.sh` as the validation/build sources of truth. Keep GitHub Actions pinned to full commit SHAs, as the existing workflows do.

## Documentation

- Keep the root [README.md](README.md) for the collection overview, release downloads and publishing workflow. Put wallpaper-specific behaviour, architecture and development commands in [Game of Life/README.md](Game%20of%20Life/README.md) or [City Simulation/README.md](City%20Simulation/README.md).
- Maintain native Game of Life installation/integration guidance in `Game of Life/NativeWallpaper/INSTALL.md`; keep fallback setup in the existing `Game of Life/Setup.txt` and `Game of Life/Packaging/Wallpaper-Setup.txt`. City installation and its generated asset gallery belong in its README.
- Update the relevant existing section when behaviour, settings, compatibility, commands or release contents change. Game of Life's `INSTALL.md` and City's README/assets ship in release ZIPs; check `.github/workflows/release.yml` and the build scripts when changing packaged instructions or links.
- Match the existing style: descriptive headings, short user-facing paragraphs, numbered setup steps, fenced shell commands and relative links. Quote paths containing spaces; percent-encode spaces in Markdown link destinations. Keep gallery images beside the existing assets and provide descriptive alt text.
- Prefer updating and linking existing documentation. Add a new document only for a distinct, lasting need that does not fit an existing section, and link it from the relevant README. Do not add task summaries, implementation diaries, duplicate setup guides or Markdown that merely restates code; use concise inline comments for non-obvious algorithms or ABI assumptions.

## Pull requests

Leave pull requests you open for a human to review and merge, even after all required checks pass.

When opening a pull request, apply the appropriate labels: `bug` for bug fixes, `documentation` for documentation changes, and `enhancement` for new features or improvements. Apply multiple labels when relevant.

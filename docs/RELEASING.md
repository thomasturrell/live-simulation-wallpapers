# Publishing a release

The [Release workflow](../.github/workflows/release.yml) tests both wallpapers and builds ad-hoc signed native wallpaper ZIPs for macOS 26 or later, with Apple silicon and Intel support:

| Download | Installation and package contents |
| --- | --- |
| `Game-of-Life-Native-Wallpaper.zip` | [Game of Life installation notes](../Game%20of%20Life/NativeWallpaper/INSTALL.md) |
| `City-Simulation-Native-Wallpaper.zip` | [City Simulation installation notes](../City%20Simulation/README.md#install-on-macos) |

GitHub also provides source code ZIP and tar.gz archives for the release tag.

1. On GitHub, open **Actions → Release → Run workflow**. Select the branch you want to release from and enter a version tag such as `v1.0.0`.
2. Wait for the workflow to finish. It attaches the two native wallpaper ZIPs to a draft release. If the tag exists, the workflow builds its commit. For a new tag, the draft targets the selected branch's commit at the time you ran the workflow.
3. Open the draft from the workflow summary or the **Releases** page. Review the notes and downloads, then click **Publish release**.

Run the workflow again with the same tag to replace the two native wallpaper ZIPs on an existing draft. The workflow also removes the earlier Game of Life desktop-app and wallpaper-and-screen-saver ZIPs from that draft.

For a new tag, use the default branch if your target branch changes GitHub Actions workflow files. GitHub requires a token with Workflows write permission to create releases for those commits.

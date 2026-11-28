# Publishing a release

The [Release workflow](../.github/workflows/release.yml) tests the wallpaper packages and prepares Developer ID signed, Apple-notarised native wallpaper ZIPs for distribution outside the Mac App Store on macOS 26 or later, with Apple silicon and Intel support:

| Download | Installation and package contents |
| --- | --- |
| `Game-of-Life-Native-Wallpaper.zip` | [Game of Life installation notes](../Game%20of%20Life/NativeWallpaper/INSTALL.md) |
| `City-Simulation-Native-Wallpaper.zip` | [City Simulation installation notes](../City%20Simulation/README.md#install-on-macos) |
| `System-Design-Native-Wallpaper.zip` | [System Design installation notes](../System%20Design/README.md#install-on-macos) |

GitHub also provides source code ZIP and tar.gz archives for the release tag.

1. On GitHub, open **Actions → Release → Run workflow**. Select **main** and enter a version tag in `vMAJOR.MINOR.PATCH` format, such as `v1.0.0`. Runs from other branches or tags are skipped. Existing tags must point to commits in the selected main-branch history.
2. Wait for the build and signing jobs to finish, approving access to the `release` environment if configured. Only after every included app passes signing, notarisation, ticket stapling and Gatekeeper checks does the workflow attach the ZIPs to a draft release. If the tag exists, the workflow builds its commit. For a new tag, the draft targets main's commit at the time you ran the workflow.
3. Open the draft from the workflow summary or the **Releases** page. Review the notes and downloads, then click **Publish release**.

Run the workflow again with the same tag to replace the native wallpaper ZIPs on an existing draft and remove the earlier Game of Life desktop-app and wallpaper-and-screen-saver ZIPs. If the draft moves to a different commit, the workflow removes its previous wallpaper ZIPs before changing the target. A commit that predates System Design receives the Game of Life and City Simulation downloads only.

Published releases cannot be overwritten. The workflow never publishes the draft automatically, and changing this workflow does not start a release.

## Signing setup and safeguards

Configure the GitHub environment **release** with `APPLE_CERTIFICATE_BASE64` (the Base64-encoded Developer ID Application certificate and private key exported as a password-protected `.p12`), `APPLE_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID` and `APPLE_APP_SPECIFIC_PASSWORD`.

Allow **main** as a deployment branch in that environment. A tags-only `v*` environment rule will block this manually dispatched workflow, even when the release input names an existing tag. Protect main and require review of workflow and signing-script changes; restrict who can dispatch releases and manage tags. An environment reviewer is recommended. The workflow's own branch check does not protect secrets from a different workflow, so the environment's deployment-branch restriction is essential.

Builds and package tests run without Apple credentials or a repository write token. A separate macOS runner uses the signing scripts from the selected main commit, never scripts from the release tag, and never launches the downloaded apps. It imports exactly one valid Developer ID Application identity for the configured team into a temporary keychain. The extension keeps its existing App Sandbox entitlement; both extension and carrier use Hardened Runtime and secure timestamps, with no runtime exceptions. The extension is signed before the enclosing app. Unexpected additional executable code stops the release until the signing order is updated.

The workflow submits each signed app and its nested extension using `notarytool`, requires an `Accepted` result and checks Apple's diagnostic log. It staples the ticket to the app, verifies the ticket and signatures, and requires Gatekeeper acceptance. It then rebuilds the original ZIP layout, extracts that final ZIP and repeats verification. Apple silicon and Intel slices must both be present. See [Apple's command-line notarisation workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

Credentials are available only to the signing step, and the temporary keychain, certificate and authentication logs are removed on success, failure or cancellation, with an additional cleanup step. GitHub-hosted runner disposal covers forced termination that prevents cleanup. Only verified ZIPs are passed to the separate job that can modify the release draft. Intermediate artifacts expire after one day. Development scripts and pull request CI keep their existing ad-hoc signing behaviour.

Apple submissions wait up to 20 minutes per app. A rejection, timeout, signing error, missing architecture, failed ticket check or Gatekeeper denial prevents draft uploads; rerun the workflow after resolving the cause. Notarisation checks do not establish that the undocumented wallpaper interface works on every macOS update. Before publishing, download the draft assets on macOS 26 or later, open each app from Applications, confirm its Wallpaper and Screen Saver choices, and test lock/unlock. Check both Apple silicon and Intel Macs when available.

To test release orchestration on macOS without Apple credentials or GitHub requests, run `python3 -m unittest discover -s .github/scripts/tests -v` from the repository root. These tests replace the signing and network tools; a real release run is still required to validate the certificate, Apple's service and Gatekeeper acceptance.

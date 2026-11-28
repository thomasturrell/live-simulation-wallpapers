#!/bin/bash
# Run only on the isolated release runner, using scripts from the workflow commit.
set +x
set -euo pipefail
umask 077

private="$RUNNER_TEMP/wallpaper-signing"
keychain="$private/signing.keychain-db"
output="$RUNNER_TEMP/release-assets"

cleanup() {
    local status=0
    if [[ -e "$keychain" ]]; then
        security delete-keychain "$keychain" >/dev/null 2>&1 || status=1
    fi
    rm -rf "$private"
    return "$status"
}

if [[ "${1:-}" == cleanup ]]; then
    cleanup
    exit
fi

finish() {
    local status=$?
    trap - EXIT
    if ! cleanup; then
        echo '::error::Could not delete the temporary signing keychain.'
        status=1
    fi
    if [[ "$status" != 0 ]]; then rm -rf "$output"; fi
    exit "$status"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
    echo "::error::$1"
    exit 1
}

for secret in APPLE_CERTIFICATE_BASE64 APPLE_CERTIFICATE_PASSWORD APPLE_ID APPLE_TEAM_ID APPLE_APP_SPECIFIC_PASSWORD; do
    [[ -n "${!secret:-}" ]] || fail "Missing release environment secret: $secret."
done
[[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || fail 'Invalid Apple Team ID.'
[[ "${RELEASE_HAS_SYSTEM_DESIGN:-}" =~ ^(true|false)$ ]] || fail 'Missing wallpaper package selection.'

mkdir "$private"
mkdir "$output"
password="$(openssl rand -base64 32)"
printf '::add-mask::%s\n' "$password"
printf '%s' "$APPLE_CERTIFICATE_BASE64" | base64 -D > "$private/certificate.p12"
security create-keychain -p "$password" "$keychain" >/dev/null 2>&1
security set-keychain-settings -lut 7200 "$keychain"
security unlock-keychain -p "$password" "$keychain"
if ! security import "$private/certificate.p12" -P "$APPLE_CERTIFICATE_PASSWORD" \
    -k "$keychain" -T /usr/bin/codesign >/dev/null 2>&1; then
    fail 'Could not import the Developer ID certificate and private key.'
fi
rm "$private/certificate.p12"
if ! security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
    -k "$password" "$keychain" >/dev/null 2>&1; then
    fail 'Could not allow codesign to use the temporary signing key.'
fi

# Select exactly one valid Developer ID Application identity from this keychain
# and team. Never fall back to an ad-hoc, development or App Store identity.
identities=($(security find-identity -v -p codesigning "$keychain" |
    awk -v team="$APPLE_TEAM_ID" '$2 ~ /^[A-Fa-f0-9]+$/ && length($2) == 40 &&
        index($0, "\"Developer ID Application: ") && index($0, "(" team ")\"") { print $2 }'))
[[ "${#identities[@]}" == 1 ]] || fail 'Expected one valid Developer ID Application identity for the configured team.'
identity="${identities[0]}"
if ! xcrun notarytool store-credentials wallpaper-release --keychain "$keychain" \
    --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" >/dev/null 2>&1; then
    fail 'Could not validate and store Apple notarisation credentials.'
fi
unset APPLE_CERTIFICATE_BASE64 APPLE_CERTIFICATE_PASSWORD APPLE_ID APPLE_APP_SPECIFIC_PASSWORD password

names=(Game-of-Life City-Simulation)
apps=('Game of Life Wallpaper.app' 'City Simulation Wallpaper.app')
extensions=(LifeWallpaper CityWallpaper)
if [[ "$RELEASE_HAS_SYSTEM_DESIGN" == true ]]; then
    names+=(System-Design)
    apps+=('System Design Wallpaper.app')
    extensions+=(DesignWallpaper)
fi

verify_app() {
    local app="$1" extension="$2" binary
    codesign --verify --strict --deep --all-architectures "$app"
    # Gatekeeper assesses the enclosing app; the extension is checked explicitly
    # for Developer ID trust, team, timestamp and Hardened Runtime as well.
    for binary in "$extension" "$app"; do
        codesign --verify --strict --all-architectures \
            -R "anchor apple generic and certificate leaf[subject.OU] = \"$APPLE_TEAM_ID\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists" "$binary"
        codesign --display --verbose=4 "$binary" 2> "$private/signature.txt"
        grep -q 'flags=.*runtime' "$private/signature.txt" || fail 'Hardened Runtime is missing.'
        grep -q '^Timestamp=' "$private/signature.txt" || fail 'A secure signing timestamp is missing.'
    done
    codesign --display --entitlements - --xml "$extension" > "$private/extension-entitlements.plist" 2>/dev/null
    codesign --display --entitlements - --xml "$app" > "$private/app-entitlements.plist" 2>/dev/null
    python3 - "$private" <<'PY'
import pathlib
import plistlib
import sys

private = pathlib.Path(sys.argv[1])
expected = plistlib.loads(pathlib.Path("NativeWallpaperSupport/Sandbox.plist").read_bytes())
extension = plistlib.loads((private / "extension-entitlements.plist").read_bytes())
host = (private / "app-entitlements.plist").read_bytes()
if extension != expected or (host and plistlib.loads(host)):
    raise SystemExit("Unexpected release entitlements")
PY
}

for index in "${!names[@]}"; do
    name="${names[$index]}"
    archive="$name-Native-Wallpaper.zip"
    stage="$private/$name"
    mkdir "$stage"
    # Reject path traversal and symlinks before extracting a build artifact.
    python3 - "$RUNNER_TEMP/unsigned-assets/$archive" <<'PY'
import pathlib
import stat
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    for entry in archive.infolist():
        path = pathlib.PurePosixPath(entry.filename)
        if path.is_absolute() or ".." in path.parts or stat.S_ISLNK(entry.external_attr >> 16):
            raise SystemExit("Unsafe path in wallpaper archive")
PY
    ditto -x -k "$RUNNER_TEMP/unsigned-assets/$archive" "$stage"
    app="$stage/${apps[$index]}"
    extension="$app/Contents/Extensions/${extensions[$index]}.appex"
    host_binary="$app/Contents/MacOS/InstallWallpaper"
    extension_binary="$extension/Contents/MacOS/${extensions[$index]}"
    [[ -f "$host_binary" && -f "$extension_binary" ]] || fail "Missing code in $archive."

    # These packages contain two executables and no frameworks or helpers.
    # Fail closed if packaging adds code that needs a new inside-out signing step.
    while IFS= read -r -d '' binary; do
        if file -b "$binary" | grep -q 'Mach-O'; then
            [[ "$binary" == "$host_binary" || "$binary" == "$extension_binary" ]] || \
                fail "Unexpected nested code in $archive. Update the signing order."
        fi
    done < <(find "$stage" -type f -print0)
    lipo -verify_arch arm64 x86_64 "$host_binary"
    lipo -verify_arch arm64 x86_64 "$extension_binary"

    # Preserve the extension sandbox. The carrier needs no entitlements or
    # Hardened Runtime exceptions. Do not inherit old ad-hoc entitlements.
    codesign --force --sign "$identity" --keychain "$keychain" --options runtime --timestamp \
        --entitlements NativeWallpaperSupport/Sandbox.plist "$extension"
    codesign --force --sign "$identity" --keychain "$keychain" --options runtime --timestamp "$app"
    verify_app "$app" "$extension"
    # Submit the signed app, including its extension. Never submit a build ZIP
    # that still contains an ad-hoc signed copy of the app.
    submission="$private/$name.zip"
    ditto -c -k --keepParent "$app" "$submission"
    submit_status=0
    xcrun notarytool submit "$submission" --keychain "$keychain" \
        --keychain-profile wallpaper-release --wait --timeout 20m --output-format json \
        > "$private/submission.json" 2> "$private/submission-error.txt" || submit_status=$?
    submission_id="$(jq -r '.id // empty' "$private/submission.json")"
    if [[ -n "$submission_id" ]]; then
        # Only show diagnostic fields; raw authentication/tool output stays private.
        xcrun notarytool log "$submission_id" --keychain "$keychain" \
            --keychain-profile wallpaper-release "$private/notary-log.json" >/dev/null 2>&1 || \
            fail "Could not retrieve the notarisation log for $name."
        jq '{status, issues}' "$private/notary-log.json"
    fi
    [[ "$submit_status" == 0 ]] && jq -e '.status == "Accepted"' "$private/submission.json" >/dev/null || \
        fail "Apple did not accept $name for notarisation. See the diagnostic fields above."

    # Tickets attach to apps, not ZIPs. Staple the enclosing app after Apple has
    # accepted all its nested code, then rebuild the original download layout.
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    verify_app "$app" "$extension"
    spctl --assess --type execute --verbose=4 "$app"
    ditto -c -k "$stage" "$output/$archive"

    # Check the exact bytes users will extract, including the stapled ticket.
    extracted="$private/verify-$name"
    ditto -x -k "$output/$archive" "$extracted"
    verify_app "$extracted/${apps[$index]}" "$extracted/${apps[$index]}/Contents/Extensions/${extensions[$index]}.appex"
    xcrun stapler validate "$extracted/${apps[$index]}"
    spctl --assess --type execute --verbose=4 "$extracted/${apps[$index]}"
    echo "Verified $archive."
done

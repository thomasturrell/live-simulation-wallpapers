#!/bin/bash
# Run only on the isolated release runner, using scripts from the workflow commit.
set +x
set -euo pipefail
umask 077

private="$RUNNER_TEMP/wallpaper-signing"
keychain="$private/signing.keychain-db"
output="$RUNNER_TEMP/release-assets"
pending="$RUNNER_TEMP/notarisation-pending"
phase="${1:-submit}"
search_list="$private/original-keychain-search-list.txt"

# Preserve each original path as a separate argument (including spaces).
# An empty original list is also valid.
set_search_list() {
    local entry
    while IFS= read -r entry; do
        set -- "$@" "$entry"
    done < "$search_list"
    security list-keychains -d user -s "$@"
}

cleanup() {
    local status=0
    if [[ -f "$search_list" ]]; then
        set_search_list >/dev/null 2>&1 || status=1
    fi
    if [[ -e "$keychain" ]]; then
        security delete-keychain "$keychain" >/dev/null 2>&1 || status=1
    fi
    rm -rf "$private"
    return "$status"
}

if [[ "$phase" == cleanup ]]; then
    cleanup
    exit
fi

finish() {
    local status=$?
    trap - EXIT
    if ! cleanup; then
        echo '::error::Could not restore the keychain search list or delete the temporary signing keychain.'
        status=1
    fi
    if [[ "$status" != 0 ]]; then
        if [[ "$phase" == submit ]]; then rm -rf "$pending"; fi
        if [[ "$phase" == finalize ]]; then rm -rf "$output"; fi
    fi
    exit "$status"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
    echo "::error::$1"
    exit 1
}

[[ "$phase" == submit || "$phase" == finalize ]] || fail 'Expected submit or finalize.'
required=(APPLE_ID APPLE_TEAM_ID APPLE_APP_SPECIFIC_PASSWORD)
if [[ "$phase" == submit ]]; then
    required+=(APPLE_CERTIFICATE_BASE64 APPLE_CERTIFICATE_PASSWORD)
fi
for secret in "${required[@]}"; do
    [[ -n "${!secret:-}" ]] || fail "Missing release environment secret: $secret."
done
# A pasted newline is not part of an Apple ID, Team ID or app-specific password.
# Do not trim the certificate export password, where whitespace may be intentional.
for credential in APPLE_ID APPLE_TEAM_ID APPLE_APP_SPECIFIC_PASSWORD; do
    printf -v "$credential" '%s' "$(printf '%s' "${!credential}" | python3 -c 'import sys; sys.stdout.write(sys.stdin.read().strip())')"
    [[ -n "${!credential}" ]] || fail "Empty release environment secret: $credential."
done
[[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || fail 'Invalid Apple Team ID.'
[[ "${RELEASE_HAS_SYSTEM_DESIGN:-}" =~ ^(true|false)$ ]] || fail 'Missing wallpaper package selection.'

mkdir "$private"
if [[ "$phase" == submit ]]; then
    mkdir "$pending"
else
    [[ -d "$pending" ]] || fail 'Missing signed notarisation packages; run the submission job first.'
    mkdir "$output"
fi
password="$(openssl rand -base64 32)"
printf '::add-mask::%s\n' "$password"
# Capture the original list before creating the keychain, since creation may
# itself change the user's search list. Save only a complete, parsed list.
if ! security list-keychains -d user |
    python3 -c 'import shlex, sys; sys.stdout.writelines(path + "\n" for path in shlex.split(sys.stdin.read()))' > "$search_list.tmp"; then
    fail 'Could not read the original keychain search list.'
fi
mv "$search_list.tmp" "$search_list"
security create-keychain -p "$password" "$keychain" >/dev/null 2>&1
security set-keychain-settings -lut 14400 "$keychain"
security unlock-keychain -p "$password" "$keychain"
if [[ "$phase" == submit ]]; then
    printf '%s' "$APPLE_CERTIFICATE_BASE64" | base64 -D > "$private/certificate.p12"
    if ! security import "$private/certificate.p12" -P "$APPLE_CERTIFICATE_PASSWORD" \
        -k "$keychain" -T /usr/bin/codesign >/dev/null 2>&1; then
        fail 'Could not import the Developer ID certificate and private key.'
    fi
    rm "$private/certificate.p12"
    if ! security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
        -k "$password" "$keychain" >/dev/null 2>&1; then
        fail 'Could not allow codesign to use the temporary signing key.'
    fi
fi
# codesign uses the user search list for certificate-chain lookups even when
# --keychain explicitly selects the keychain for the signing identity.
if ! set_search_list "$keychain"; then
    fail 'Could not add the temporary signing keychain to the user search list.'
fi

if [[ "$phase" == submit ]]; then
    # Select exactly one valid Developer ID Application identity from this keychain
    # and team. Never fall back to an ad-hoc, development or App Store identity.
    identities=($(security find-identity -v -p codesigning "$keychain" |
        awk -v team="$APPLE_TEAM_ID" '$2 ~ /^[A-Fa-f0-9]+$/ && length($2) == 40 &&
            index($0, "\"Developer ID Application: ") && index($0, "(" team ")\"") { print $2 }'))
    [[ "${#identities[@]}" == 1 ]] || fail 'Expected one valid Developer ID Application identity for the configured team.'
    identity="${identities[0]}"
fi
# Never publish raw notarytool output. Redact credentials and neutralise annotations.
show_notary_diagnostic() {
    python3 - "$1" <<'PY'
import os
import pathlib
import re
import sys

message = pathlib.Path(sys.argv[1]).read_text(errors="replace")
secrets = {variant for name, value in os.environ.items() if name.startswith("APPLE_")
           for variant in (value, value.strip()) if variant}
for secret in sorted(secrets, key=len, reverse=True):
    message = message.replace(secret, "[REDACTED]")
message = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", message)
message = re.sub(r"[\x00-\x08\x0b-\x1f\x7f]", "", message)
message = re.sub(r"[\w.+-]+@[\w.-]+", "[REDACTED EMAIL]", message)
message = re.sub(r"\b[a-zA-Z]{4}(?:-[a-zA-Z]{4}){3}\b", "[REDACTED PASSWORD]", message)
for line in message[:4000].splitlines():
    # Prefix every line so tool output cannot be interpreted as a workflow command.
    print("notarytool: " + line)
PY
}
if ! xcrun notarytool store-credentials wallpaper-release --keychain "$keychain" \
    --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" > "$private/notary-credentials.txt" 2>&1; then
    show_notary_diagnostic "$private/notary-credentials.txt"
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
            -R "=anchor apple generic and certificate leaf[subject.OU] = \"$APPLE_TEAM_ID\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists" "$binary"
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

check_archive() {
    # Reject path traversal and symlinks before extracting a build artifact.
    python3 - "$1" <<'PY'
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
}

valid_submission_id() {
    [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

archive_sha256() {
    shasum -a 256 "$1" | awk '{print $1}'
}

summary() {
    printf '%s\n' "$1"
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        printf '%s\n' "$1" >> "$GITHUB_STEP_SUMMARY"
    fi
}

if [[ "$phase" == submit ]]; then
    for index in "${!names[@]}"; do
        name="${names[$index]}"
        archive="$name-Native-Wallpaper.zip"
        stage="$private/$name"
        mkdir "$stage"
        check_archive "$RUNNER_TEMP/unsigned-assets/$archive"
        ditto -x -k "$RUNNER_TEMP/unsigned-assets/$archive" "$stage"
        # Finder metadata and resource forks invalidate strict distribution signing.
        xattr -cr "$stage"
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
        for architecture in arm64 x86_64; do
            lipo "$host_binary" -verify_arch "$architecture"
            lipo "$extension_binary" -verify_arch "$architecture"
        done

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
        if ! xcrun notarytool submit "$submission" --keychain "$keychain" \
            --keychain-profile wallpaper-release --output-format json \
            > "$private/submission.json" 2> "$private/submission-error.txt"; then
            show_notary_diagnostic "$private/submission-error.txt"
            fail "Could not submit $name to Apple."
        fi
        if ! submission_id="$(jq -er '.id | select(type == "string")' "$private/submission.json")" ||
            ! valid_submission_id "$submission_id"; then
            fail "Apple did not return a valid submission ID for $name."
        fi
        # Record the ID as soon as Apple returns it; do not wait for analysis.
        summary "Submitted $name to Apple: $submission_id"
        # Retain exactly the signed package, not a freshly rebuilt or re-signed app.
        ditto -c -k "$stage" "$pending/$archive"
        jq -n --arg id "$submission_id" --arg sha256 "$(archive_sha256 "$pending/$archive")" \
            '{id: $id, sha256: $sha256}' > "$pending/$name.json"
    done
    exit 0
fi

# This job can be retried independently using the immutable artifact from the
# successful submission job. It never has the signing private key.
submission_ids=()
statuses=()
for index in "${!names[@]}"; do
    name="${names[$index]}"
    archive="$name-Native-Wallpaper.zip"
    if ! submission_id="$(jq -er '.id | select(type == "string")' "$pending/$name.json")" ||
        ! valid_submission_id "$submission_id"; then
        fail "Missing or invalid saved submission ID for $name."
    fi
    expected_digest="$(jq -er '.sha256 | select(type == "string")' "$pending/$name.json")"
    [[ "$expected_digest" =~ ^[0-9a-f]{64}$ ]] &&
        [[ "$expected_digest" == "$(archive_sha256 "$pending/$archive")" ]] ||
        fail "Signed package digest does not match the submission manifest for $name."
    submission_ids[$index]="$submission_id"
    statuses[$index]="In Progress"
    stage="$private/$name"
    mkdir "$stage"
    check_archive "$pending/$archive"
    ditto -x -k "$pending/$archive" "$stage"
    app="$stage/${apps[$index]}"
    extension="$app/Contents/Extensions/${extensions[$index]}.appex"
    verify_app "$app" "$extension"
done

# Poll all outstanding submissions against one shared deadline, rather than
# waiting for each app in turn. Apple's processing continues after this job ends.
wait_limit="${NOTARISATION_WAIT_SECONDS:-7200}"
[[ "$wait_limit" =~ ^(0|[1-9][0-9]{0,4})$ ]] || fail 'Invalid notarisation wait limit.'
deadline=$((SECONDS + wait_limit))
while :; do
    outstanding=0
    for index in "${!names[@]}"; do
        [[ "${statuses[$index]}" == Accepted ]] && continue
        name="${names[$index]}"
        submission_id="${submission_ids[$index]}"
        if ! xcrun notarytool info "$submission_id" --keychain "$keychain" \
            --keychain-profile wallpaper-release --output-format json \
            > "$private/notary-info.json" 2> "$private/notary-error.txt"; then
            show_notary_diagnostic "$private/notary-error.txt"
            fail "Could not query Apple for $name ($submission_id). Re-run failed jobs to retry the existing submission."
        fi
        if ! status="$(jq -er --arg id "$submission_id" \
            'select((.id | ascii_downcase) == ($id | ascii_downcase)) | .status | select(type == "string")' \
            "$private/notary-info.json")"; then
            fail "Unexpected notarisation response for $name ($submission_id). Re-run failed jobs to check again."
        fi
        case "$status" in
            "In Progress")
                outstanding=$((outstanding + 1))
                ;;
            Accepted|Invalid|Rejected)
                summary "Apple notarisation for $name ($submission_id): $status"
                if ! xcrun notarytool log "$submission_id" --keychain "$keychain" \
                    --keychain-profile wallpaper-release "$private/notary-log.json" \
                    >/dev/null 2> "$private/notary-error.txt"; then
                    show_notary_diagnostic "$private/notary-error.txt"
                    fail "Could not retrieve the notarisation log for $name ($submission_id)."
                fi
                # Print only diagnostic fields from Apple's JSON log, not credentials
                # or raw tool output. A single prefixed line cannot inject commands.
                printf 'notarytool log: %s\n' "$(jq -c '{status, issues}' "$private/notary-log.json")"
                [[ "$status" == Accepted ]] || fail "Apple rejected $name ($submission_id): $status. See the notarisation log above."
                statuses[$index]=Accepted
                ;;
            *)
                fail "Unknown notarisation status for $name ($submission_id). Re-run failed jobs to check again."
                ;;
        esac
    done
    [[ "$outstanding" == 0 ]] && break
    remaining=$((deadline - SECONDS))
    if [[ "$remaining" -le 0 ]]; then
        for index in "${!names[@]}"; do
            if [[ "${statuses[$index]}" != Accepted ]]; then
                summary "Still In Progress: ${names[$index]} (${submission_ids[$index]})"
            fi
        done
        fail "Apple notarisation is still in progress after $wait_limit seconds, not rejected. Re-run failed jobs later to resume without rebuilding or resubmitting."
    fi
    echo "$outstanding Apple notarisation submission(s) still in progress."
    if [[ "$remaining" -gt 60 ]]; then remaining=60; fi
    sleep "$remaining"
done

# Only after every package is accepted may any of them be packaged for release.
for index in "${!names[@]}"; do
    name="${names[$index]}"
    archive="$name-Native-Wallpaper.zip"
    stage="$private/$name"
    app="$stage/${apps[$index]}"
    extension="$app/Contents/Extensions/${extensions[$index]}.appex"
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

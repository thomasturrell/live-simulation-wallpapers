#!/bin/bash
set -euo pipefail

if [[ ! "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "::error::Enter a release tag in vMAJOR.MINOR.PATCH format, such as v1.0.0."
    exit 1
fi

# The authenticated release listing includes drafts and distinguishes a missing
# release from an API error.
draft="$(gh api --paginate --slurp "repos/$GH_REPO/releases?per_page=100" |
    jq -c --arg tag "$RELEASE_TAG" 'first(.[][] | select(.tag_name == $tag)) // null')"
if [[ "$(jq -r '.draft' <<< "$draft")" == false ]]; then
    echo "::error::Release $RELEASE_TAG is already published."
    exit 1
fi

# Matching refs can return tags with the same prefix. Resolve only the exact
# tag through the commits API, which also handles annotated tags.
has_tag="$(gh api "repos/$GH_REPO/git/matching-refs/tags/$RELEASE_TAG" |
    jq -r --arg ref "refs/tags/$RELEASE_TAG" 'any(.[]; .ref == $ref)')"
commit="$GITHUB_SHA"
if [[ "$has_tag" == true ]]; then
    commit="$(gh api "repos/$GH_REPO/commits/tags/$RELEASE_TAG" --jq .sha)"
fi

remove_draft_assets() {
    local asset name
    for asset in "$@"; do
        name="${asset##*/}"
        if jq -e --arg name "$name" 'any(.assets[]; .name == $name)' <<< "$draft" >/dev/null; then
            gh release delete-asset "$RELEASE_TAG" "$name" --yes
        fi
    done
}

case "$1" in
    resolve)
        printf 'commit=%s\n' "$commit" >> "$GITHUB_OUTPUT"
        ;;
    upload)
        if [[ "$commit" != "$RELEASE_COMMIT" || "$(git rev-parse HEAD)" != "$RELEASE_COMMIT" ]]; then
            echo "::error::The release commit changed during the build. Run the workflow again for $RELEASE_TAG."
            exit 1
        fi

        assets=(
            "$RUNNER_TEMP/release-assets/Game-of-Life-Native-Wallpaper.zip"
            "$RUNNER_TEMP/release-assets/City-Simulation-Native-Wallpaper.zip"
        )
        if [[ -f "System Design/Package.swift" ]]; then
            assets+=("$RUNNER_TEMP/release-assets/System-Design-Native-Wallpaper.zip")
        fi
        for asset in "${assets[@]}"; do
            if [[ ! -s "$asset" ]]; then
                echo "::error::Missing native wallpaper release ZIP $asset."
                exit 1
            fi
        done

        if [[ "$draft" == null ]]; then
            target=(--target "$commit")
            if [[ "$has_tag" == true ]]; then
                target=(--verify-tag)
            fi
            notes="$(printf 'See the [release download guide](%s/%s#release-downloads) for ZIP contents and macOS requirements.\n\nThe macOS apps and embedded extensions are Developer ID signed with Hardened Runtime, notarised by Apple and distributed with stapled tickets.' \
                "$GITHUB_SERVER_URL" "$GH_REPO")"
            draft_url="$(gh release create "$RELEASE_TAG" "${assets[@]}" \
                --draft "${target[@]}" --generate-notes --notes "$notes")"
        else
            obsolete=(Game-of-Life-Desktop-App.zip Game-of-Life-Wallpaper-and-Screen-Saver.zip)
            if [[ ! -f "System Design/Package.swift" ]]; then obsolete+=(System-Design-Native-Wallpaper.zip); fi
            retarget=false
            if [[ "$has_tag" == false && "$(jq -r '.target_commitish' <<< "$draft")" != "$commit" ]]; then
                retarget=true
                # Even builds absent from the new commit must go before the target moves.
                remove_draft_assets "${assets[@]}" "${obsolete[@]}"
                gh release edit "$RELEASE_TAG" --target "$commit"
            fi
            gh release upload "$RELEASE_TAG" "${assets[@]}" --clobber
            if [[ "$retarget" == false ]]; then remove_draft_assets "${obsolete[@]}"; fi
            notes="$(jq -r '.body // ""' <<< "$draft")"
            if [[ "$notes" == *'The macOS bundles use ad-hoc signing.'* ]]; then
                notes="${notes//The macOS bundles use ad-hoc signing./The macOS apps and embedded extensions are Developer ID signed with Hardened Runtime, notarised by Apple and distributed with stapled tickets.}"
                gh release edit "$RELEASE_TAG" --notes "$notes"
            fi
            draft_url="$(jq -r '.html_url' <<< "$draft")"
        fi

        printf 'Review and publish the [draft release for %s](%s).\n' \
            "$RELEASE_TAG" "$draft_url" >> "$GITHUB_STEP_SUMMARY"
        ;;
esac

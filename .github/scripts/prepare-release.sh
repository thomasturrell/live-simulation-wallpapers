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

case "$1" in
    resolve)
        printf 'commit=%s\n' "$commit" >> "$GITHUB_OUTPUT"
        ;;
    upload)
        if [[ "$commit" != "$RELEASE_COMMIT" || "$(git rev-parse HEAD)" != "$RELEASE_COMMIT" ]]; then
            echo "::error::The release commit changed during the build. Run the workflow again for $RELEASE_TAG."
            exit 1
        fi

        shopt -s nullglob
        assets=("$RUNNER_TEMP/release-assets/"*.zip)
        if [[ "${#assets[@]}" != 4 ]]; then
            echo "::error::Expected four release ZIPs before preparing the draft."
            exit 1
        fi

        if [[ "$draft" == null ]]; then
            target=(--target "$commit")
            if [[ "$has_tag" == true ]]; then
                target=(--verify-tag)
            fi
            draft_url="$(gh release create "$RELEASE_TAG" "${assets[@]}" \
                --draft "${target[@]}" --generate-notes \
                --notes "The macOS bundles use ad-hoc signing.")"
        else
            if [[ "$has_tag" == false && "$(jq -r '.target_commitish' <<< "$draft")" != "$commit" ]]; then
                # Remove old builds before retargeting so an interrupted upload
                # cannot leave binaries from another commit on the new target.
                for asset in "${assets[@]}"; do
                    name="${asset##*/}"
                    if jq -e --arg name "$name" 'any(.assets[]; .name == $name)' <<< "$draft" >/dev/null; then
                        gh release delete-asset "$RELEASE_TAG" "$name" --yes
                    fi
                done
                gh release edit "$RELEASE_TAG" --target "$commit"
            fi
            gh release upload "$RELEASE_TAG" "${assets[@]}" --clobber
            draft_url="$(jq -r '.html_url' <<< "$draft")"
        fi

        printf 'Review and publish the [draft release for %s](%s).\n' \
            "$RELEASE_TAG" "$draft_url" >> "$GITHUB_STEP_SUMMARY"
        ;;
esac

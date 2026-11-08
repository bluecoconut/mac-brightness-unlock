#!/bin/bash
set -euo pipefail

gh_api() {
  gh api -H 'User-Agent: OpenAI File Downloader, XaiImageApiFetch/1.0' "$@"
}
if ! release_id=$(gh_api "repos/$GITHUB_REPOSITORY/releases/tags/$GITHUB_REF_NAME" --jq .id 2>/dev/null); then
  release_id=$(gh_api --method POST "repos/$GITHUB_REPOSITORY/releases" \
    -f tag_name="$GITHUB_REF_NAME" \
    -f name="Brightness Unlock $GITHUB_REF_NAME" \
    -F generate_release_notes=true --jq .id)
fi
for asset in Brightness-Unlock.zip Brightness-Unlock.zip.sha256; do
  existing_id=$(gh_api "repos/$GITHUB_REPOSITORY/releases/$release_id/assets" \
    --jq ".[] | select(.name == \"$asset\") | .id")
  if [ -n "$existing_id" ]; then
    gh_api --method DELETE "repos/$GITHUB_REPOSITORY/releases/assets/$existing_id"
  fi
  gh_api --method POST \
    "https://uploads.github.com/repos/$GITHUB_REPOSITORY/releases/$release_id/assets?name=$asset" \
    -H 'Content-Type: application/octet-stream' \
    --input "build/$asset" --jq .browser_download_url
done

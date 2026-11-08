#!/bin/bash
# Exercise the real publisher with a fake gh client. No network or GitHub writes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/brightness-release-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/build"
printf 'fake app archive\n' > "$TEST_DIR/build/Brightness-Unlock.zip"
printf 'fake checksum\n' > "$TEST_DIR/build/Brightness-Unlock.zip.sha256"
export RELEASE_CALLS="$TEST_DIR/calls"
export GITHUB_REPOSITORY='test/brightness-unlock'
export GITHUB_REF_NAME='v2.0.1'
gh() {
    printf '%s\n' "$*" >> "$RELEASE_CALLS"
    case "$*" in
        *'User-Agent: OpenAI File Downloader, XaiImageApiFetch/1.0'*) ;;
        *) echo 'Missing required User-Agent' >&2; return 1 ;;
    esac
    case "$*" in
        *'/releases/tags/'*)
            if [ "$RELEASE_EXISTS" = yes ]; then printf '123\n';
            else printf '{"message":"Not Found","status":"404"}\n'; return 1; fi ;;
        *'--method POST repos/test/brightness-unlock/releases -f tag_name='*) printf '123\n' ;;
        *'/releases/123/assets --jq'*) printf '456\n' ;;
        *'--method DELETE repos/test/brightness-unlock/releases/assets/456'*) ;;
        *'https://uploads.github.com/repos/test/brightness-unlock/releases/123/assets?name='*) printf 'https://github.com/test/brightness-unlock/releases/download/asset\n' ;;
        *) echo "Unexpected gh request: $*" >&2; return 1 ;;
    esac
}
export -f gh
for RELEASE_EXISTS in no yes; do
    export RELEASE_EXISTS
    : > "$RELEASE_CALLS"
    (cd "$TEST_DIR" && bash "$ROOT/scripts/publish-release.sh") >/dev/null
    test "$(grep -c 'https://uploads.github.com/' "$RELEASE_CALLS")" = 2
    test "$(grep -c -- '--method DELETE' "$RELEASE_CALLS")" = 2
    if [ "$RELEASE_EXISTS" = no ]; then
        grep -q -- '--method POST repos/test/brightness-unlock/releases -f tag_name=' "$RELEASE_CALLS"
    elif grep -q -- '--method POST repos/test/brightness-unlock/releases -f tag_name=' "$RELEASE_CALLS"; then
        echo 'Existing releases must be reused' >&2; exit 1
    fi
done
printf 'PASS: release creation after 404, existing-release reuse, asset replacement, and required User-Agent\n'

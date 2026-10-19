#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/scripts/release-common.sh"
otosaku_load_env "$ROOT"

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/otosaku-tts-release-common.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT

MOCK_BIN="$TEMP_DIR/bin"
mkdir -p "$MOCK_BIN"

cat >"$MOCK_BIN/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-C" && "${3:-}" == "remote" && "${4:-}" == "get-url" && "${5:-}" == "origin" ]]; then
  printf '%s\n' "https://github.com/example/otosaku-tts.git"
  exit 0
fi

echo "unexpected git invocation: $*" >&2
exit 1
EOF
chmod +x "$MOCK_BIN/git"

export PATH="$MOCK_BIN:$PATH"

expected_release_root="$ROOT/.release/$(otosaku_release_version)"
[[ "$(otosaku_release_root "$ROOT")" == "$expected_release_root" ]]
[[ "$(otosaku_release_artifacts_dir "$ROOT")" == "$expected_release_root/artifacts" ]]
[[ "$(otosaku_release_package_cache_dir "$ROOT")" == "$expected_release_root/PackageCache" ]]

[[ "$(otosaku_appcast_feed_url "$ROOT")" == "https://raw.githubusercontent.com/example/otosaku-tts/main/appcast.xml" ]]
[[ "$(otosaku_release_download_url_prefix "$ROOT" local)" == "file://$expected_release_root/artifacts/" ]]
[[ "$(otosaku_release_download_url_prefix "$ROOT" publish)" == "https://github.com/example/otosaku-tts/releases/download/$(otosaku_release_tag)/" ]]

export APPCAST_URL="https://example.invalid/feed.xml"
[[ "$(otosaku_appcast_feed_url "$ROOT")" == "https://example.invalid/feed.xml" ]]
unset APPCAST_URL

export RELEASE_DOWNLOAD_URL_PREFIX="https://downloads.example.invalid/otosaku-tts"
[[ "$(otosaku_release_download_url_prefix "$ROOT" publish)" == "https://downloads.example.invalid/otosaku-tts/" ]]
unset RELEASE_DOWNLOAD_URL_PREFIX

echo "Release common helper tests passed."

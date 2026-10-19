#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/scripts/release.sh"
EXPECTED_RELEASE_TAG="$(otosaku_release_tag)"
EXPECTED_MARKETING_VERSION="$MARKETING_VERSION"

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/otosaku-tts-release-appcast-notes.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT

export APPCAST_PATH="$TEMP_DIR/appcast.xml"

cat >"$APPCAST_PATH" <<'XML'
<rss>
  <channel>
    <item>
      <title>OtosakuTTS __MARKETING_VERSION__</title>
      <enclosure url="https://example.invalid/OtosakuTTS.dmg" length="123" type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML
sed -i '' "s/__MARKETING_VERSION__/${EXPECTED_MARKETING_VERSION}/g" "$APPCAST_PATH"

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

annotate_appcast_release_notes

grep -Fq "<sparkle:releaseNotesLink>https://github.com/example/otosaku-tts/releases/tag/${EXPECTED_RELEASE_TAG}</sparkle:releaseNotesLink>" "$APPCAST_PATH"

echo "Release appcast notes tests passed."

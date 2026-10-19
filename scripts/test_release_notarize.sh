#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/scripts/release.sh"

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/otosaku-tts-release-notarize.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT

export RELEASE_SKIP_NOTARIZATION=0
export DMG_PATH="$TEMP_DIR/OtosakuTTS.dmg"
export NOTARYTOOL_PROFILE="OtosakuTTS Notary"
export XCRUN_LOG="$TEMP_DIR/xcrun.log"

touch "$DMG_PATH"

MOCK_BIN="$TEMP_DIR/bin"
mkdir -p "$MOCK_BIN"

cat >"$MOCK_BIN/xcrun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"${XCRUN_LOG:?}"
if [[ "${1:-}" == "notarytool" && "${2:-}" == "submit" ]]; then
  cat <<'JSON'
{"id":"TEST-SUBMISSION-ID","status":"Accepted"}
JSON
fi
exit 0
EOF
chmod +x "$MOCK_BIN/xcrun"

export PATH="$MOCK_BIN:$PATH"

notarize_dmg

grep -Fq "notarytool submit $DMG_PATH --keychain-profile OtosakuTTS Notary --wait" "$XCRUN_LOG"
grep -Fq "stapler staple $DMG_PATH" "$XCRUN_LOG"
grep -Fq "stapler validate $DMG_PATH" "$XCRUN_LOG"

echo "Release notarization flow tests passed."

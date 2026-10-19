#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/scripts/release.sh"

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/otosaku-tts-release-signing.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT

export RELEASE_SKIP_SIGNING=0
export DEVELOPER_ID_IDENTITY="Developer ID Application: Test User (TEAMID)"
export APP_PATH="$TEMP_DIR/Example.app"
export CODESIGN_LOG="$TEMP_DIR/codesign.log"
export SPCTL_LOG="$TEMP_DIR/spctl.log"

mkdir -p "$APP_PATH/Contents/Frameworks/Foo.framework" "$APP_PATH/Contents/MacOS"
touch "$APP_PATH/Contents/MacOS/OtosakuTTS"

mkdir -p \
  "$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS" \
  "$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS" \
  "$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc/Contents/MacOS"
touch \
  "$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle" \
  "$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" \
  "$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater" \
  "$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader" \
  "$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer"
ln -s B "$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/Current"
SPARKLE_FRAMEWORK_PATH=$(cd "$APP_PATH/Contents/Frameworks/Sparkle.framework" && pwd -P)
SPARKLE_VERSION_PATH=$(cd "$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B" && pwd -P)

MOCK_BIN="$TEMP_DIR/bin"
mkdir -p "$MOCK_BIN"

cat >"$MOCK_BIN/codesign" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"${CODESIGN_LOG:?}"
exit 0
EOF
chmod +x "$MOCK_BIN/codesign"

export PATH="$MOCK_BIN:$PATH"

sign_release_app

grep -Fq -- "--force --timestamp --options runtime --sign Developer ID Application: Test User (TEAMID) $APP_PATH/Contents/Frameworks/Foo.framework" "$CODESIGN_LOG"
grep -Fq -- "--force --timestamp --options runtime --sign Developer ID Application: Test User (TEAMID) $SPARKLE_VERSION_PATH/Sparkle" "$CODESIGN_LOG"
grep -Fq -- "--force --timestamp --options runtime --sign Developer ID Application: Test User (TEAMID) $SPARKLE_VERSION_PATH/Updater.app/Contents/MacOS/Updater" "$CODESIGN_LOG"
grep -Fq -- "--force --timestamp --options runtime --sign Developer ID Application: Test User (TEAMID) $SPARKLE_VERSION_PATH/XPCServices/Downloader.xpc/Contents/MacOS/Downloader" "$CODESIGN_LOG"
grep -Fq -- "--force --timestamp --options runtime --sign Developer ID Application: Test User (TEAMID) $SPARKLE_VERSION_PATH/XPCServices/Installer.xpc/Contents/MacOS/Installer" "$CODESIGN_LOG"
grep -Fq -- "--force --timestamp --options runtime --sign Developer ID Application: Test User (TEAMID) $SPARKLE_VERSION_PATH/Updater.app" "$CODESIGN_LOG"
grep -Fq -- "--force --timestamp --options runtime --sign Developer ID Application: Test User (TEAMID) $SPARKLE_VERSION_PATH/XPCServices/Downloader.xpc" "$CODESIGN_LOG"
grep -Fq -- "--force --timestamp --options runtime --sign Developer ID Application: Test User (TEAMID) $SPARKLE_VERSION_PATH/XPCServices/Installer.xpc" "$CODESIGN_LOG"
grep -Fq -- "--force --timestamp --options runtime --sign Developer ID Application: Test User (TEAMID) $SPARKLE_VERSION_PATH" "$CODESIGN_LOG"
grep -Fq -- "--force --timestamp --options runtime --sign Developer ID Application: Test User (TEAMID) $SPARKLE_FRAMEWORK_PATH" "$CODESIGN_LOG"
grep -Fq -- "--force --timestamp --options runtime --entitlements $ROOT/Example/OtosakuTTS.entitlements --sign Developer ID Application: Test User (TEAMID) $APP_PATH" "$CODESIGN_LOG"
grep -Fq -- "--verify --deep --strict --verbose=2 $APP_PATH" "$CODESIGN_LOG"

echo "Release signing flow tests passed."

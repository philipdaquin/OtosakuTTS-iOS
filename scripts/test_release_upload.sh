#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/scripts/release.sh"

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/otosaku-tts-release-upload.XXXXXX")
ROOT_APPCAST="$ROOT/appcast.xml"
trap 'rm -rf "$TEMP_DIR"; rm -f "$ROOT_APPCAST"' EXIT

export ROOT
export MODE=upload
export RELEASE_SKIP_SIGNING=1
export RELEASE_SKIP_NOTARIZATION=1
export RELEASE_ARCHS="arm64 x86_64"
export RELEASE_BASE_DIR="$TEMP_DIR/release"
export RELEASE_ROOT="$RELEASE_BASE_DIR"
export MARKETING_VERSION="1.2.3"
export BUILD_NUMBER="4"
export ARTIFACTS_DIR="$RELEASE_ROOT/artifacts"
export SOURCEPACKAGES_DIR="$RELEASE_ROOT/SourcePackages"
export DERIVED_DATA_DIR="$RELEASE_ROOT/DerivedData"
export SPARKLE_DERIVED_DATA_DIR="$RELEASE_ROOT/SparkleDerivedData"
export PACKAGE_CACHE_DIR="$RELEASE_ROOT/PackageCache"
export STAGING_DIR="$RELEASE_ROOT/dmg-stage"
export HOME_DIR="$RELEASE_ROOT/home"
export CACHE_DIR="$RELEASE_ROOT/cache"
export APP_PATH="$RELEASE_ROOT/DerivedData/Build/Products/Release/Example.app"
export DMG_PATH="$ARTIFACTS_DIR/OtosakuTTS-macos-universal-1.2.3-4.dmg"
export ZIP_PATH="$ARTIFACTS_DIR/OtosakuTTS-macos-universal-1.2.3-4.zip"
export APPCAST_PATH="$ARTIFACTS_DIR/appcast.xml"
export DOWNLOAD_URL_PREFIX="https://github.com/example/otosaku-tts/releases/download/v1.2.3/"
export APPCAST_FEED_URL="https://raw.githubusercontent.com/example/otosaku-tts/main/appcast.xml"
export SPARKLE_PRIVATE_KEY_FILE="$TEMP_DIR/private-ed25519.key"
APPCAST_INPUT_DIR="$ARTIFACTS_DIR/appcast-input"

mkdir -p "$ARTIFACTS_DIR" "$SOURCEPACKAGES_DIR" "$SPARKLE_DERIVED_DATA_DIR/Build/Products/Release" "$APP_PATH" "$HOME_DIR" "$CACHE_DIR"
touch "$ZIP_PATH" "$DMG_PATH"
printf '%s\n' "dummy" >"$SPARKLE_PRIVATE_KEY_FILE"

MOCK_BIN="$TEMP_DIR/bin"
mkdir -p "$MOCK_BIN"

cat >"$MOCK_BIN/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >"${GH_LOG:-/tmp/gh.log}"
exit 0
EOF
chmod +x "$MOCK_BIN/gh"

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

cat >"$TEMP_DIR/fake-generate-appcast" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

out=""
prefix=""
input_dir=""
while (($#)); do
  case "$1" in
    --download-url-prefix)
      prefix="$2"
      shift 2
      ;;
    -o)
      out="$2"
      shift 2
      ;;
    --ed-key-file)
      shift 2
      ;;
    *)
      input_dir="$1"
      shift
      ;;
  esac
done

printf '%s\n' "$prefix" >"${FAKE_APPCAST_PREFIX_LOG:?}"
printf '%s\n' "$input_dir" >"${FAKE_APPCAST_INPUT_LOG:?}"
cat >"$out" <<XML
<appcast prefix="$prefix"></appcast>
XML
EOF
chmod +x "$TEMP_DIR/fake-generate-appcast"

export PATH="$MOCK_BIN:$PATH"
export GH_LOG="$TEMP_DIR/gh.log"
export FAKE_APPCAST_PREFIX_LOG="$TEMP_DIR/prefix.log"
export FAKE_APPCAST_INPUT_LOG="$TEMP_DIR/input.log"

assert_contains() {
  local needle="$1"
  local file="$2"
  if ! grep -Fq "$needle" "$file"; then
    echo "ERROR: expected '$needle' in $file" >&2
    echo "--- $file ---" >&2
    sed -n '1,40p' "$file" >&2 || true
    exit 1
  fi
}

build_release_app() { :; }
resolve_signing_options() { :; }
sign_release_app() { :; }
package_dmg() { :; }
notarize_dmg() { :; }
create_zip() { :; }
build_sparkle_tool() { printf '%s\n' "$TEMP_DIR/fake-generate-appcast"; }

upload_release
generate_appcast
cp "$APPCAST_PATH" "$ROOT/appcast.xml"

assert_contains "release upload v1.2.3" "$GH_LOG"
assert_contains "$DMG_PATH" "$GH_LOG"
assert_contains "$ZIP_PATH" "$GH_LOG"
assert_contains "https://github.com/example/otosaku-tts/releases/download/v1.2.3/" "$FAKE_APPCAST_PREFIX_LOG"
assert_contains "$APPCAST_INPUT_DIR" "$FAKE_APPCAST_INPUT_LOG"
assert_contains '<appcast prefix="https://github.com/example/otosaku-tts/releases/download/v1.2.3/"></appcast>' "$APPCAST_PATH"

echo "Release upload flow tests passed."

#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/otosaku-tts-release-doctor.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT

MOCK_BIN="$TEMP_DIR/bin"
mkdir -p "$MOCK_BIN"

cat >"$MOCK_BIN/xcodebuild" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
cat >"$MOCK_BIN/hdiutil" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
cat >"$MOCK_BIN/ditto" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
cat >"$MOCK_BIN/xcrun" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
cat >"$MOCK_BIN/git" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-C" && "${3:-}" == "remote" && "${4:-}" == "get-url" && "${5:-}" == "origin" ]]; then
  printf '%s\n' "https://github.com/example/otosaku-tts.git"
  exit 0
fi

echo "unexpected git invocation: $*" >&2
exit 1
MOCK
cat >"$MOCK_BIN/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "secret" && "${2:-}" == "list" ]]; then
  cat <<'SECRETS'
DEVELOPER_ID_IDENTITY
DEVELOPER_ID_CERTIFICATE_P12_BASE64
DEVELOPER_ID_CERTIFICATE_PASSWORD
NOTARYTOOL_API_KEY_ID
NOTARYTOOL_API_ISSUER_ID
NOTARYTOOL_API_KEY_P8
SPARKLE_PUBLIC_ED_KEY
SPARKLE_PRIVATE_KEY_FILE
SECRETS
  exit 0
fi

echo "unexpected gh invocation: $*" >&2
exit 1
MOCK
chmod +x "$MOCK_BIN"/*

SPARKLE_KEY="$TEMP_DIR/private-ed25519.key"
printf '%s\n' "dummy" >"$SPARKLE_KEY"

export PATH="$MOCK_BIN:$PATH"
export RELEASE_ENV_FILE="$TEMP_DIR/empty.env"
export DEVELOPER_ID_IDENTITY="Developer ID Application: Test User (TEAMID)"
export NOTARYTOOL_API_KEY_ID="KEYID"
export NOTARYTOOL_API_ISSUER_ID="ISSUER"
export NOTARYTOOL_API_KEY_P8="PRIVATEKEY"
export SPARKLE_PRIVATE_KEY_FILE="$SPARKLE_KEY"
export SPARKLE_PUBLIC_ED_KEY="PUBLICKEY"

touch "$RELEASE_ENV_FILE"

"$ROOT/scripts/release-doctor.sh" --github >"$TEMP_DIR/pass.out"
grep -Fq "OtosakuTTS release inputs look ready." "$TEMP_DIR/pass.out"
grep -Fq "OK GitHub secret: DEVELOPER_ID_CERTIFICATE_P12_BASE64" "$TEMP_DIR/pass.out"
grep -Fq "OK GitHub secret: SPARKLE_PRIVATE_KEY or SPARKLE_PRIVATE_KEY_FILE" "$TEMP_DIR/pass.out"

cat >"$MOCK_BIN/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "secret" && "${2:-}" == "list" ]]; then
  cat <<'SECRETS'
DEVELOPER_ID_IDENTITY
NOTARYTOOL_API_KEY_ID
NOTARYTOOL_API_ISSUER_ID
NOTARYTOOL_API_KEY_P8
SPARKLE_PUBLIC_ED_KEY
SPARKLE_PRIVATE_KEY_FILE
SECRETS
  exit 0
fi

echo "unexpected gh invocation: $*" >&2
exit 1
MOCK
chmod +x "$MOCK_BIN/gh"

if "$ROOT/scripts/release-doctor.sh" --github >"$TEMP_DIR/fail.out" 2>"$TEMP_DIR/fail.err"; then
  echo "ERROR: release doctor accepted missing certificate secrets." >&2
  exit 1
fi

grep -Fq "FAIL missing GitHub secret: DEVELOPER_ID_CERTIFICATE_P12_BASE64" "$TEMP_DIR/fail.out"
grep -Fq "FAIL missing GitHub secret: DEVELOPER_ID_CERTIFICATE_PASSWORD" "$TEMP_DIR/fail.out"
grep -Fq "OtosakuTTS release inputs are not ready." "$TEMP_DIR/fail.err"

echo "Release doctor tests passed."

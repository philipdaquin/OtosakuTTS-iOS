#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/scripts/release-common.sh"
otosaku_load_env "$ROOT"
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/otosaku-tts-release-notes.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT

OUTPUT="$TEMP_DIR/release-notes.md"

MOCK_BIN="$TEMP_DIR/bin"
mkdir -p "$MOCK_BIN"

cat >"$MOCK_BIN/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-C" && "${3:-}" == "describe" && "${4:-}" == "--tags" && "${5:-}" == "--abbrev=0" && "${6:-}" == "--match" && "${7:-}" == "v*" ]]; then
  printf '%s\n' "v0.0.1"
  exit 0
fi

if [[ "${1:-}" == "-C" && "${3:-}" == "log" && "${4:-}" == "--format=%s" ]]; then
  cat <<'SUBJECTS'
Add Sparkle auto-update support
Stop category selection from starting scans
Use stapler validation for DMG release
SUBJECTS
  exit 0
fi

echo "unexpected git invocation: $*" >&2
exit 1
EOF
chmod +x "$MOCK_BIN/git"

PATH="$MOCK_BIN:$PATH" bash "$ROOT/scripts/release-notes.sh" "$MARKETING_VERSION" "$OUTPUT"

grep -Fq "OtosakuTTS $MARKETING_VERSION" "$OUTPUT"
grep -Fq "Generated from commit subjects" "$OUTPUT"
grep -Fq "## Added" "$OUTPUT"
grep -Fq "Add Sparkle auto-update support" "$OUTPUT"
grep -Fq "Stop category selection from starting scans" "$OUTPUT"
if grep -Fq "Use stapler validation for DMG release" "$OUTPUT"; then
  echo "ERROR: release plumbing should not appear in drafted release notes." >&2
  exit 1
fi

echo "Release notes draft tests passed."

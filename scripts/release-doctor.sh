#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
source "$SCRIPT_DIR/release-common.sh"
otosaku_load_env "$ROOT"

REQUIRED_GITHUB_SECRETS=(
  DEVELOPER_ID_IDENTITY
  DEVELOPER_ID_CERTIFICATE_P12_BASE64
  DEVELOPER_ID_CERTIFICATE_PASSWORD
  NOTARYTOOL_API_KEY_ID
  NOTARYTOOL_API_ISSUER_ID
  NOTARYTOOL_API_KEY_P8
  SPARKLE_PUBLIC_ED_KEY
)

print_usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") [--github]

Checks that the OtosakuTTS release pipeline has the inputs needed to publish
a signed, notarized GitHub Release.

Options:
  --github   Check required GitHub Actions secret names with gh.
EOF
}

check_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'FAIL missing command: %s\n' "$command_name"
    return 1
  fi

  printf 'OK command: %s\n' "$command_name"
}

check_file() {
  local path="$1"
  local label="$2"

  if [[ ! -e "$path" ]]; then
    printf 'FAIL missing %s: %s\n' "$label" "$path"
    return 1
  fi

  printf 'OK %s: %s\n' "$label" "$path"
}

check_env_value() {
  local name="$1"

  if [[ -z "${!name:-}" ]]; then
    printf 'FAIL missing env: %s\n' "$name"
    return 1
  fi

  printf 'OK env: %s\n' "$name"
}

check_local_inputs() {
  local status=0

  check_file "$ROOT/Example/Example.xcodeproj" "Xcode project" || status=1
  check_file "$ROOT/version.env" "version file" || status=1
  check_file "$ROOT/CHANGELOG.md" "changelog" || status=1
  check_file "$ROOT/Example/OtosakuTTS.entitlements" "release entitlements" || status=1
  check_command xcodebuild || status=1
  check_command hdiutil || status=1
  check_command ditto || status=1
  check_command xcrun || status=1
  check_command gh || status=1

  check_env_value DEVELOPER_ID_IDENTITY || status=1
  check_env_value SPARKLE_PUBLIC_ED_KEY || status=1

  if [[ -z "${NOTARYTOOL_PROFILE:-}" ]]; then
    check_env_value NOTARYTOOL_API_KEY_ID || status=1
    check_env_value NOTARYTOOL_API_ISSUER_ID || status=1
    if [[ -z "${NOTARYTOOL_API_KEY_FILE:-}" && -z "${NOTARYTOOL_API_KEY_P8:-}" ]]; then
      printf 'FAIL missing env: NOTARYTOOL_API_KEY_FILE or NOTARYTOOL_API_KEY_P8\n'
      status=1
    else
      printf 'OK env: NOTARYTOOL_API_KEY_FILE or NOTARYTOOL_API_KEY_P8\n'
    fi
  else
    printf 'OK env: NOTARYTOOL_PROFILE\n'
  fi

  if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
    if [[ -f "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
      printf 'OK env: SPARKLE_PRIVATE_KEY_FILE\n'
    else
      printf 'FAIL SPARKLE_PRIVATE_KEY_FILE does not exist: %s\n' "$SPARKLE_PRIVATE_KEY_FILE"
      status=1
    fi
  elif [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    printf 'OK env: SPARKLE_PRIVATE_KEY\n'
  else
    printf 'FAIL missing env: SPARKLE_PRIVATE_KEY_FILE or SPARKLE_PRIVATE_KEY\n'
    status=1
  fi

  return "$status"
}

check_github_secrets() {
  local repo secret names status=0

  repo=$(otosaku_repo_slug)

  if ! command -v gh >/dev/null 2>&1; then
    printf 'FAIL missing command: gh\n'
    return 1
  fi

  if ! names=$(gh secret list --repo "$repo" --json name --jq '.[].name'); then
    printf 'FAIL could not list GitHub secrets for %s\n' "$repo"
    return 1
  fi

  for secret in "${REQUIRED_GITHUB_SECRETS[@]}"; do
    if grep -Fxq "$secret" <<<"$names"; then
      printf 'OK GitHub secret: %s\n' "$secret"
    else
      printf 'FAIL missing GitHub secret: %s\n' "$secret"
      status=1
    fi
  done

  if grep -Fxq SPARKLE_PRIVATE_KEY <<<"$names" || grep -Fxq SPARKLE_PRIVATE_KEY_FILE <<<"$names"; then
    printf 'OK GitHub secret: SPARKLE_PRIVATE_KEY or SPARKLE_PRIVATE_KEY_FILE\n'
  else
    printf 'FAIL missing GitHub secret: SPARKLE_PRIVATE_KEY or SPARKLE_PRIVATE_KEY_FILE\n'
    status=1
  fi

  return "$status"
}

main() {
  local check_github=0 status=0

  while (($#)); do
    case "$1" in
      --github)
        check_github=1
        ;;
      -h|--help)
        print_usage
        return 0
        ;;
      *)
        printf 'ERROR: Unknown option: %s\n' "$1" >&2
        print_usage
        return 1
        ;;
    esac
    shift
  done

  check_local_inputs || status=1

  if [[ "$check_github" == "1" ]]; then
    check_github_secrets || status=1
  fi

  if [[ "$status" == "0" ]]; then
    printf 'OtosakuTTS release inputs look ready.\n'
  else
    printf 'OtosakuTTS release inputs are not ready.\n' >&2
  fi

  return "$status"
}

main "$@"

#!/usr/bin/env bash

otosaku_repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

otosaku_load_env() {
  local root="$1"
  local release_env_file="${RELEASE_ENV_FILE:-$root/release.env}"

  source "$root/version.env"

  if [[ -f "$release_env_file" ]]; then
    set -a
    source "$release_env_file"
    set +a
  fi
}

otosaku_release_version() {
  printf '%s-%s' "$MARKETING_VERSION" "$BUILD_NUMBER"
}

otosaku_release_tag() {
  printf 'v%s' "$MARKETING_VERSION"
}

otosaku_repo_slug() {
  local origin
  origin=$(git -C "$(otosaku_repo_root)" remote get-url origin 2>/dev/null || true)
  local slug

  case "$origin" in
    https://github.com/*/*.git)
      slug="${origin#https://github.com/}"
      ;;
    https://github.com/*)
      slug="${origin#https://github.com/}"
      ;;
    git@github.com:*/*.git)
      slug="${origin#git@github.com:}"
      ;;
    git@github.com:*)
      slug="${origin#git@github.com:}"
      ;;
    *)
      slug='philipdaquin/OtosakuTTS-iOS'
      ;;
  esac

  printf '%s' "${slug%.git}"
}

otosaku_arch_label() {
  local raw="${1:-arm64 x86_64}"
  local normalized has_arm64=0 has_x86_64=0 arch

  normalized=$(printf '%s' "$raw" | tr ',' ' ')
  for arch in $normalized; do
    case "$arch" in
      arm64) has_arm64=1 ;;
      x86_64) has_x86_64=1 ;;
    esac
  done

  if [[ "$has_arm64" == "1" && "$has_x86_64" == "1" ]]; then
    printf 'macos-universal'
    return
  fi
  if [[ "$has_arm64" == "1" ]]; then
    printf 'macos-arm64'
    return
  fi
  if [[ "$has_x86_64" == "1" ]]; then
    printf 'macos-x86_64'
    return
  fi

  printf 'macos-%s' "$(printf '%s' "$normalized" | tr ' ' '+')"
}

otosaku_release_root() {
  local root="$1"
  printf '%s/.release/%s' "$root" "$(otosaku_release_version)"
}

otosaku_release_artifacts_dir() {
  local root="$1"
  printf '%s/artifacts' "$(otosaku_release_root "$root")"
}

otosaku_release_sourcepackages_dir() {
  local root="$1"
  printf '%s/SourcePackages' "$(otosaku_release_root "$root")"
}

otosaku_release_derived_data_dir() {
  local root="$1"
  printf '%s/DerivedData' "$(otosaku_release_root "$root")"
}

otosaku_release_sparkle_derived_data_dir() {
  local root="$1"
  printf '%s/SparkleDerivedData' "$(otosaku_release_root "$root")"
}

otosaku_release_package_cache_dir() {
  local root="$1"
  printf '%s/PackageCache' "$(otosaku_release_root "$root")"
}

otosaku_release_app_path() {
  local root="$1"
  printf '%s/Build/Products/Release/Example.app' "$(otosaku_release_derived_data_dir "$root")"
}

otosaku_release_dmg_path() {
  local root="$1"
  printf '%s/OtosakuTTS-%s-%s.dmg' "$(otosaku_release_artifacts_dir "$root")" \
    "$(otosaku_arch_label "${RELEASE_ARCHS:-arm64 x86_64}")" \
    "$(otosaku_release_version)"
}

otosaku_release_zip_path() {
  local root="$1"
  printf '%s/OtosakuTTS-%s-%s.zip' "$(otosaku_release_artifacts_dir "$root")" \
    "$(otosaku_arch_label "${RELEASE_ARCHS:-arm64 x86_64}")" \
    "$(otosaku_release_version)"
}

otosaku_release_appcast_path() {
  local root="$1"
  printf '%s/appcast.xml' "$(otosaku_release_artifacts_dir "$root")"
}

otosaku_release_staging_dir() {
  local root="$1"
  printf '%s/dmg-stage' "$(otosaku_release_root "$root")"
}

otosaku_release_generate_appcast_tool() {
  local sparkle_checkout="$1"
  local sparkle_derived_data="$2"
  local sparkle_package_cache="$3"
  local tool

  xcodebuild \
    -project "$sparkle_checkout/Sparkle.xcodeproj" \
    -scheme generate_appcast \
    -configuration Release \
    -derivedDataPath "$sparkle_derived_data" \
    -packageCachePath "$sparkle_package_cache" \
    -disableAutomaticPackageResolution \
    -skipPackageUpdates \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    build >/dev/null

  tool=$(find "$sparkle_derived_data/Build/Products/Release" -maxdepth 1 -type f -perm -111 -name generate_appcast | head -n 1)
  if [[ -z "$tool" ]]; then
    echo "ERROR: Could not locate Sparkle generate_appcast tool after building it." >&2
    return 1
  fi

  printf '%s\n' "$tool"
}

otosaku_appcast_feed_url() {
  local root="$1"
  local slug tag

  slug=$(otosaku_repo_slug)

  if [[ -n "${APPCAST_URL:-}" ]]; then
    printf '%s' "${APPCAST_URL%/}"
    return
  fi

  printf 'https://raw.githubusercontent.com/%s/main/appcast.xml' "$slug"
}

otosaku_release_download_url_prefix() {
  local root="$1"
  local mode="${2:-local}"
  local slug tag

  slug=$(otosaku_repo_slug)
  tag=$(otosaku_release_tag)

  if [[ -n "${RELEASE_DOWNLOAD_URL_PREFIX:-}" ]]; then
    printf '%s' "${RELEASE_DOWNLOAD_URL_PREFIX%/}/"
    return
  fi

  case "$mode" in
    publish|upload)
      printf 'https://github.com/%s/releases/download/%s/' "$slug" "$tag"
      ;;
    *)
      printf 'file://%s/' "$(otosaku_release_artifacts_dir "$root")"
      ;;
  esac
}

otosaku_notarytool_args() {
  if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
    printf '%s\n' "--keychain-profile" "$NOTARYTOOL_PROFILE"
    return 0
  fi

  if [[ -n "${NOTARYTOOL_API_KEY_FILE:-}" && -n "${NOTARYTOOL_API_KEY_ID:-}" && -n "${NOTARYTOOL_API_ISSUER_ID:-}" ]]; then
    printf '%s\n' "--key" "$NOTARYTOOL_API_KEY_FILE" "--key-id" "$NOTARYTOOL_API_KEY_ID" "--issuer" "$NOTARYTOOL_API_ISSUER_ID"
    return 0
  fi

  return 1
}

otosaku_sparkle_key_file() {
  local root="$1"

  if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
    if [[ ! -f "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
      echo "ERROR: SPARKLE_PRIVATE_KEY_FILE does not point to an existing file." >&2
      return 1
    fi
    printf '%s\n' "$SPARKLE_PRIVATE_KEY_FILE"
    return 0
  fi

  if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    local temp_dir key_file
    temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/otosaku-tts-sparkle.XXXXXX")"
    key_file="$temp_dir/private-ed25519.key"
    umask 077
    printf '%s' "$SPARKLE_PRIVATE_KEY" > "$key_file"
    printf '%s\n' "$key_file"
    return 0
  fi

  if [[ "${RELEASE_REQUIRE_SPARKLE_KEY:-0}" == "1" ]]; then
    echo "ERROR: SPARKLE_PRIVATE_KEY_FILE or SPARKLE_PRIVATE_KEY is required for this release mode." >&2
    return 1
  fi

  return 1
}

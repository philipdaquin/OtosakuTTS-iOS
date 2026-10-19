#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
source "$SCRIPT_DIR/release-common.sh"
otosaku_load_env "$ROOT"

VERSION="${1:-${MARKETING_VERSION:-$(otosaku_release_version)}}"
OUTPUT_PATH="${2:-/dev/stdout}"
GENERATED_DATE="${RELEASE_NOTES_DATE:-$(date +%F)}"

release_base_ref() {
  local base_ref

  if base_ref=$(git -C "$ROOT" describe --tags --abbrev=0 --match 'v*' 2>/dev/null); then
    printf '%s\n' "$base_ref"
    return 0
  fi

  printf '%s\n' ""
}

should_skip_subject() {
  local subject="$1"

  case "$subject" in
    *release*|*Release*|*workflow*|*Workflow*|*appcast*|*Appcast*|*notar*|*Notar*|*signing*|*Signing*|*artifact*|*Artifact*|*doctor*|*Doctor*|*README*|*readme*)
      return 0
      ;;
  esac

  return 1
}

section_for_subject() {
  local subject="$1"

  case "$subject" in
    Add*|Added*|Introduce*|Create*|Enable*|Expose* )
      printf '%s\n' "Added"
      ;;
    Fix*|Fixed*|Stop*|Avoid*|Prevent*|Handle* )
      printf '%s\n' "Fixed"
      ;;
    Improve*|Improved*|Optimize*|Optimise*|Speed*|Harden*|Polish* )
      printf '%s\n' "Improved"
      ;;
    Remove*|Removed* )
      printf '%s\n' "Removed"
      ;;
    *)
      printf '%s\n' "Changed"
      ;;
  esac
}

sanitize_subject() {
  local subject="$1"
  subject="${subject#feat: }"
  subject="${subject#fix: }"
  subject="${subject#docs: }"
  subject="${subject#chore: }"
  printf '%s' "$subject"
}

write_notes() {
  local base_ref range subject section
  local -a added=()
  local -a changed=()
  local -a fixed=()
  local -a improved=()
  local -a removed=()

  base_ref=$(release_base_ref)
  if [[ -n "$base_ref" ]]; then
    range="${base_ref}..HEAD"
  else
    range="HEAD"
  fi

  while IFS= read -r subject; do
    [[ -z "$subject" ]] && continue
    if should_skip_subject "$subject"; then
      continue
    fi

    subject=$(sanitize_subject "$subject")
    section=$(section_for_subject "$subject")
    case "$section" in
      Added) added+=("$subject") ;;
      Fixed) fixed+=("$subject") ;;
      Improved) improved+=("$subject") ;;
      Removed) removed+=("$subject") ;;
      *) changed+=("$subject") ;;
    esac
  done < <(git -C "$ROOT" log --format='%s' $range)

  {
    printf '# OtosakuTTS %s\n' "$VERSION"
    printf 'Generated from commit subjects on %s.\n\n' "$GENERATED_DATE"

    if ((${#added[@]})); then
      printf '## Added\n'
      for subject in "${added[@]}"; do
        printf '%s\n' "- $subject"
      done
      printf '\n'
    fi

    if ((${#changed[@]})); then
      printf '## Changed\n'
      for subject in "${changed[@]}"; do
        printf '%s\n' "- $subject"
      done
      printf '\n'
    fi

    if ((${#fixed[@]})); then
      printf '## Fixed\n'
      for subject in "${fixed[@]}"; do
        printf '%s\n' "- $subject"
      done
      printf '\n'
    fi

    if ((${#improved[@]})); then
      printf '## Improved\n'
      for subject in "${improved[@]}"; do
        printf '%s\n' "- $subject"
      done
      printf '\n'
    fi

    if ((${#removed[@]})); then
      printf '## Removed\n'
      for subject in "${removed[@]}"; do
        printf '%s\n' "- $subject"
      done
      printf '\n'
    fi

    printf 'Edit this draft before publishing if you want to trim or reword the summary.\n'
  } >"$OUTPUT_PATH"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  write_notes
fi

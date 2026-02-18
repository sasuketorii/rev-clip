#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0" .sh)"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_YML_REL="src/Revclip/project.yml"
INFO_PLIST_REL="src/Revclip/Revclip/Info.plist"
PROJECT_YML="$PROJECT_ROOT/$PROJECT_YML_REL"
INFO_PLIST="$PROJECT_ROOT/$INFO_PLIST_REL"
PLISTBUDDY="/usr/libexec/PlistBuddy"

log() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
}

warn() {
  printf '[%s] WARN: %s\n' "$SCRIPT_NAME" "$*" >&2
}

die() {
  printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
}

usage() {
  cat <<'EOF'
Usage:
  ./scripts/bump-version.sh <version>
  ./scripts/bump-version.sh <version> --tag
  ./scripts/bump-version.sh <version> --tag --push

Options:
  --tag     Create git commit + tag.
  --push    Push commit and tag to remote (requires --tag).
  -h, --help
            Show this help.

Version format:
  v0.0.19 or 0.0.19
EOF
}

ensure_required_files() {
  [[ -f "$PROJECT_YML" ]] || die "project.yml not found: $PROJECT_YML"
  [[ -f "$INFO_PLIST" ]] || die "Info.plist not found: $INFO_PLIST"
  [[ -x "$PLISTBUDDY" ]] || die "PlistBuddy not found at $PLISTBUDDY"
}

read_project_yml_short_version() {
  local value
  value="$(sed -nE 's/^[[:space:]]*CFBundleShortVersionString:[[:space:]]*"([^"]+)".*/\1/p' "$PROJECT_YML" | head -n1)"
  [[ -n "$value" ]] || die "Failed to read CFBundleShortVersionString from $PROJECT_YML"
  printf '%s\n' "$value"
}

read_project_yml_build_version() {
  local value
  value="$(sed -nE 's/^[[:space:]]*CFBundleVersion:[[:space:]]*"([^"]+)".*/\1/p' "$PROJECT_YML" | head -n1)"
  [[ -n "$value" ]] || die "Failed to read CFBundleVersion from $PROJECT_YML"
  printf '%s\n' "$value"
}

read_info_plist_value() {
  local key="$1"
  local value
  value="$("$PLISTBUDDY" -c "Print :$key" "$INFO_PLIST" 2>/dev/null || true)"
  [[ -n "$value" ]] || die "Failed to read $key from $INFO_PLIST"
  printf '%s\n' "$value"
}

update_project_yml_versions() {
  local short_version="$1"
  local build_version="$2"

  sed -i '' -E "s/(CFBundleShortVersionString:[[:space:]]*\")[^\"]*(\")/\1${short_version}\2/" "$PROJECT_YML"
  sed -i '' -E "s/(CFBundleVersion:[[:space:]]*\")[^\"]*(\")/\1${build_version}\2/" "$PROJECT_YML"
}

update_info_plist_versions() {
  local short_version="$1"
  local build_version="$2"

  "$PLISTBUDDY" -c "Set :CFBundleShortVersionString $short_version" "$INFO_PLIST"
  "$PLISTBUDDY" -c "Set :CFBundleVersion $build_version" "$INFO_PLIST"
}

ensure_git_repo() {
  git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not a git repository: $PROJECT_ROOT"
}

warn_if_other_uncommitted_changes() {
  local other_changes
  other_changes="$(git -C "$PROJECT_ROOT" status --porcelain --untracked-files=all | grep -Ev '^.. (src/Revclip/project\.yml|src/Revclip/Revclip/Info\.plist)$' || true)"
  if [[ -n "$other_changes" ]]; then
    warn "Uncommitted changes outside version files detected:"
    while IFS= read -r line; do
      warn "  $line"
    done <<< "$other_changes"
  fi
}

main() {
  if [[ $# -eq 0 ]]; then
    usage >&2
    exit 1
  fi

  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  local version_input="$1"
  shift

  [[ "$version_input" != -* ]] || { usage >&2; exit 1; }

  local should_tag=false
  local should_push=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tag)
        should_tag=true
        ;;
      --push)
        should_push=true
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        exit 1
        ;;
    esac
    shift
  done

  if [[ "$should_push" == true && "$should_tag" != true ]]; then
    usage >&2
    die "--push requires --tag."
  fi

  [[ "$OSTYPE" == darwin* ]] || die "This script requires macOS."

  require_cmd sed
  ensure_required_files

  if [[ ! "$version_input" =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    usage >&2
    die "Version must match ^v?([0-9]+)\\.([0-9]+)\\.([0-9]+)$"
  fi

  local short_version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
  local build_version="${BASH_REMATCH[3]}"
  local tag_version="v${short_version}"

  local old_short_project old_build_project old_short_plist old_build_plist
  old_short_project="$(read_project_yml_short_version)"
  old_build_project="$(read_project_yml_build_version)"
  old_short_plist="$(read_info_plist_value "CFBundleShortVersionString")"
  old_build_plist="$(read_info_plist_value "CFBundleVersion")"

  if [[ "$should_tag" == true ]]; then
    require_cmd git
    ensure_git_repo
    warn_if_other_uncommitted_changes
    if git -C "$PROJECT_ROOT" rev-parse -q --verify "refs/tags/$tag_version" >/dev/null; then
      die "Tag already exists: $tag_version"
    fi
  fi

  update_project_yml_versions "$short_version" "$build_version"
  update_info_plist_versions "$short_version" "$build_version"

  local new_short_project new_build_project new_short_plist new_build_plist
  new_short_project="$(read_project_yml_short_version)"
  new_build_project="$(read_project_yml_build_version)"
  new_short_plist="$(read_info_plist_value "CFBundleShortVersionString")"
  new_build_plist="$(read_info_plist_value "CFBundleVersion")"

  [[ "$new_short_project" == "$short_version" ]] || die "project.yml CFBundleShortVersionString update failed: $new_short_project"
  [[ "$new_build_project" == "$build_version" ]] || die "project.yml CFBundleVersion update failed: $new_build_project"
  [[ "$new_short_plist" == "$short_version" ]] || die "Info.plist CFBundleShortVersionString update failed: $new_short_plist"
  [[ "$new_build_plist" == "$build_version" ]] || die "Info.plist CFBundleVersion update failed: $new_build_plist"

  log "project.yml: CFBundleShortVersionString=$new_short_project, CFBundleVersion=$new_build_project"
  log "Info.plist: CFBundleShortVersionString=$new_short_plist, CFBundleVersion=$new_build_plist"
  log "Updated: ${old_short_project} -> ${new_short_project} (build: ${old_build_project} -> ${new_build_project})"

  if [[ "$should_tag" == true ]]; then
    git -C "$PROJECT_ROOT" add "$PROJECT_YML_REL" "$INFO_PLIST_REL"

    if git -C "$PROJECT_ROOT" diff --cached --quiet -- "$PROJECT_YML_REL" "$INFO_PLIST_REL"; then
      die "No version changes detected to commit."
    fi

    git -C "$PROJECT_ROOT" commit -m "chore: bump version to $tag_version"
    git -C "$PROJECT_ROOT" tag "$tag_version"
    log "Created tag: $tag_version"

    if [[ "$should_push" == true ]]; then
      git -C "$PROJECT_ROOT" push origin "$tag_version"
      git -C "$PROJECT_ROOT" push
      log "Pushed tag and current branch."
    fi
  fi

  if [[ "$old_short_project" != "$old_short_plist" || "$old_build_project" != "$old_build_plist" ]]; then
    warn "Pre-update mismatch detected between project.yml and Info.plist."
  fi
}

main "$@"

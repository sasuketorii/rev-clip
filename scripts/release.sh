#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/release.sh v0.0.8
#   ./scripts/release.sh 0.0.8
#
# Optional environment variables:
#   CODE_SIGNING_IDENTITY   Code signing identity for xcodebuild archive (default: - for ad-hoc)
#   BUILD_NUMBER            Override CFBundleVersion (default: patch number from version tag)
#   DOWNLOAD_URL_PREFIX     Override appcast download URL prefix
#   SPARKLE_PRIVATE_KEY     Optional private EdDSA key string. If set, tools read key from stdin.
#                           If unset, Sparkle tools read the private key from Keychain.
#
# GitHub Actions secret setup (for .github/workflows/release.yml):
#   1. GitHub repository -> Settings -> Secrets and variables -> Actions
#   2. Click "New repository secret"
#   3. Name: SPARKLE_PRIVATE_KEY
#   4. Value: Sparkle private EdDSA key (output from generate_keys)

SCRIPT_NAME="$(basename "$0")"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$PROJECT_ROOT/src/Revclip"
PROJECT_YML="$PROJECT_DIR/project.yml"
INFO_PLIST="$PROJECT_DIR/Revclip/Info.plist"
XCODEPROJ="$PROJECT_DIR/Revclip.xcodeproj"

BUILD_DIR="$PROJECT_ROOT/build/release"
ARCHIVE_PATH="$BUILD_DIR/Revclip.xcarchive"
APPCAST_PATH="$BUILD_DIR/appcast.xml"
SCHEME="Revclip"
APP_NAME="Revclip"

CODE_SIGNING_IDENTITY="${CODE_SIGNING_IDENTITY:--}"

log() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
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
  ./scripts/release.sh v<major>.<minor>.<patch>
  ./scripts/release.sh <major>.<minor>.<patch>

Example:
  ./scripts/release.sh v0.0.8
  ./scripts/release.sh 0.0.8
EOF
}

sparkle_download_hint() {
  cat <<'EOF' >&2
Install Sparkle tools 2.6.4 example:
  mkdir -p /tmp/sparkle-tools
  curl -L https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz -o /tmp/sparkle-tools/sparkle.tar.xz
  tar -xJf /tmp/sparkle-tools/sparkle.tar.xz -C /tmp/sparkle-tools
  # Expected binaries:
  #   /tmp/sparkle-tools/bin/sign_update
  #   /tmp/sparkle-tools/bin/generate_appcast
EOF
}

resolve_repo_slug() {
  if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    printf '%s\n' "$GITHUB_REPOSITORY"
    return 0
  fi

  local remote_url
  remote_url="$(git -C "$PROJECT_ROOT" config --get remote.origin.url || true)"
  if [[ "$remote_url" =~ github\.com[:/]([^/]+/[^/.]+)(\.git)?$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  # Fallback for this repository
  printf '%s\n' "sasuketorii/rev-clip"
}

find_sparkle_tool() {
  local tool_name="$1"
  local alt_name="${tool_name/_/-}"
  local found
  local candidate
  local project_vendor_dir="$PROJECT_DIR/Revclip/Vendor/Sparkle"

  # 1) Project local vendor: src/Revclip/Revclip/Vendor/Sparkle/*
  for candidate in \
    "$project_vendor_dir/bin/$tool_name" \
    "$project_vendor_dir/bin/$alt_name" \
    "$project_vendor_dir/$tool_name" \
    "$project_vendor_dir/$alt_name"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  found="$(find "$project_vendor_dir" -maxdepth 8 -type f \( -name "$tool_name" -o -name "$alt_name" \) -perm -111 -print -quit 2>/dev/null || true)"
  if [[ -n "$found" ]]; then
    printf '%s\n' "$found"
    return 0
  fi

  # 2) Download cache: /tmp/sparkle-tools/bin/*
  for candidate in \
    "/tmp/sparkle-tools/bin/$tool_name" \
    "/tmp/sparkle-tools/bin/$alt_name"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  found="$(find /tmp/sparkle-tools -maxdepth 8 -type f \( -name "$tool_name" -o -name "$alt_name" \) -perm -111 -print -quit 2>/dev/null || true)"
  if [[ -n "$found" ]]; then
    printf '%s\n' "$found"
    return 0
  fi

  # 3) PATH lookup
  candidate="$(command -v "$tool_name" 2>/dev/null || true)"
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  candidate="$(command -v "$alt_name" 2>/dev/null || true)"
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  return 1
}

update_project_yml_versions() {
  local short_version="$1"
  local build_version="$2"

  [[ -f "$PROJECT_YML" ]] || die "project.yml not found: $PROJECT_YML"

  sed -i '' -E "s/(CFBundleShortVersionString:[[:space:]]*\")[^\"]*(\")/\1${short_version}\2/" "$PROJECT_YML"
  sed -i '' -E "s/(CFBundleVersion:[[:space:]]*\")[^\"]*(\")/\1${build_version}\2/" "$PROJECT_YML"
}

update_info_plist_versions() {
  local short_version="$1"
  local build_version="$2"
  local plistbuddy="/usr/libexec/PlistBuddy"

  [[ -f "$INFO_PLIST" ]] || die "Info.plist not found: $INFO_PLIST"
  [[ -x "$plistbuddy" ]] || die "PlistBuddy not found at $plistbuddy"

  "$plistbuddy" -c "Set :CFBundleShortVersionString $short_version" "$INFO_PLIST"
  "$plistbuddy" -c "Set :CFBundleVersion $build_version" "$INFO_PLIST"
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  [[ $# -eq 1 ]] || { usage >&2; die "Version tag argument is required."; }
  [[ "$OSTYPE" == darwin* ]] || die "This script requires macOS 14.0+."
  if command -v sw_vers >/dev/null 2>&1; then
    local macos_major
    macos_major="$(sw_vers -productVersion | cut -d. -f1)"
    if [[ "${macos_major}" -lt 14 ]]; then
      die "macOS 14.0+ is required. Current: $(sw_vers -productVersion)"
    fi
  fi

  local version_tag="$1"
  if [[ "$version_tag" != v* ]]; then
    version_tag="v${version_tag}"
  fi

  if [[ ! "$version_tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    die "Version must match v<major>.<minor>.<patch> (example: v0.0.8)"
  fi

  local short_version="${version_tag#v}"
  local patch_version="${BASH_REMATCH[3]}"
  local build_version="${BUILD_NUMBER:-$patch_version}"

  [[ "$build_version" =~ ^[0-9]+$ ]] || die "BUILD_NUMBER / CFBundleVersion must be numeric."

  require_cmd git
  require_cmd xcodebuild
  require_cmd hdiutil
  require_cmd ditto
  require_cmd sed

  if ! command -v xcodegen >/dev/null 2>&1; then
    die "xcodegen not found. Install it first: brew install xcodegen"
  fi

  local sign_update_tool
  sign_update_tool="$(find_sparkle_tool "sign_update" || true)"
  if [[ -z "$sign_update_tool" ]]; then
    sparkle_download_hint
    die "sign_update not found."
  fi

  local generate_appcast_tool
  generate_appcast_tool="$(find_sparkle_tool "generate_appcast" || true)"
  if [[ -z "$generate_appcast_tool" ]]; then
    sparkle_download_hint
    die "generate_appcast not found."
  fi

  local repo_slug
  repo_slug="$(resolve_repo_slug)"
  local download_url_prefix="${DOWNLOAD_URL_PREFIX:-https://github.com/${repo_slug}/releases/download/${version_tag}/}"
  local dmg_path="$BUILD_DIR/${APP_NAME}-${version_tag}.dmg"
  local app_path="$ARCHIVE_PATH/Products/Applications/${APP_NAME}.app"

  log "Version: $version_tag (short=$short_version, build=$build_version)"
  log "Bundle ID (from project.yml): com.revclip.Revclip"
  log "Updating versions in project.yml and Info.plist..."
  update_project_yml_versions "$short_version" "$build_version"
  update_info_plist_versions "$short_version" "$build_version"

  log "Regenerating Xcode project with XcodeGen..."
  (
    cd "$PROJECT_DIR"
    xcodegen generate
  )

  mkdir -p "$BUILD_DIR"
  rm -rf "$ARCHIVE_PATH"

  log "Archiving Release build..."
  xcodebuild archive \
    -project "$XCODEPROJ" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    SKIP_INSTALL=NO \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$CODE_SIGNING_IDENTITY" \
    ONLY_ACTIVE_ARCH=NO

  [[ -d "$app_path" ]] || die "Archived app not found: $app_path"

  local staging_dir="$BUILD_DIR/dmg-staging"
  rm -rf "$staging_dir"
  mkdir -p "$staging_dir"
  ditto "$app_path" "$staging_dir/${APP_NAME}.app"
  ln -s /Applications "$staging_dir/Applications"

  log "Packaging DMG..."
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    -ov \
    "$dmg_path" >/dev/null
  rm -rf "$staging_dir"

  [[ -f "$dmg_path" ]] || die "DMG generation failed: $dmg_path"

  log "Signing DMG with Sparkle EdDSA..."
  local signature
  if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    signature="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$sign_update_tool" --ed-key-file - -p "$dmg_path")"
  else
    signature="$("$sign_update_tool" -p "$dmg_path")"
  fi
  [[ -n "$signature" ]] || die "sign_update did not return a signature."

  log "Generating appcast.xml..."
  rm -f "$APPCAST_PATH"
  if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    printf '%s' "$SPARKLE_PRIVATE_KEY" | \
      "$generate_appcast_tool" \
        --ed-key-file - \
        --download-url-prefix "$download_url_prefix" \
        --link "https://github.com/${repo_slug}/releases" \
        -o "$APPCAST_PATH" \
        "$BUILD_DIR"
  else
    "$generate_appcast_tool" \
      --download-url-prefix "$download_url_prefix" \
      --link "https://github.com/${repo_slug}/releases" \
      -o "$APPCAST_PATH" \
      "$BUILD_DIR"
  fi

  [[ -f "$APPCAST_PATH" ]] || die "appcast.xml generation failed: $APPCAST_PATH"

  cat <<EOF

Release artifacts created:
  $dmg_path
  $APPCAST_PATH

Next: create/upload GitHub Release assets
  gh release create "$version_tag" "$dmg_path" "$APPCAST_PATH" --title "$version_tag" --notes "Release $version_tag"
EOF
}

main "$@"

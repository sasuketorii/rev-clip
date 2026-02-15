# Fix Task: CI workflow — Update app name references from Revclip to Revpy

## Permissions
- Main branch OK. No worktree/branch needed.

## Issue
The PRODUCT_NAME was changed to "Revpy" so the .app bundle is now "Revpy.app". But the CI workflow `.github/workflows/release.yml` still references "Revclip.app" and "Revclip" in several places.

## File to Fix
`.github/workflows/release.yml`

### Changes needed:

1. **Line 141**: `Revclip.app` → `Revpy.app` (archived app path)
2. **Line 147**: `Revclip.app` → `Revpy.app` (exported app path)
3. **Line 198**: `Revclip-${GITHUB_REF_NAME}.dmg` → `Revpy-${GITHUB_REF_NAME}.dmg` (DMG filename)
4. **Line 202**: `Revclip.app` → `Revpy.app` (ditto staging)
5. **Line 206**: `-volname "Revclip"` → `-volname "Revpy"` (DMG volume name)

### DO NOT change:
- `SCHEME: Revclip` (line 16) — this is the Xcode scheme/target name, not the product name
- `PROJECT_DIR: src/Revclip` (line 15) — this is the directory path
- `Revclip.xcodeproj` (line 125) — this is the project filename
- `Revclip.xcarchive` (line 18) — this is the archive filename (derived from scheme)

## No build verification needed — this is a CI-only change.

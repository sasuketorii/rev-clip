# Coder Task: Revert ALL "Revpy" back to "Revclip"

## Permissions
- Main branch OK. No worktree/branch needed.
- You may edit any file under `src/Revclip/` and `.github/`.

## Context
The service was renamed from "Revclip" to "Revpy" in v0.0.13, but we need to revert ALL of that rename. Nobody has downloaded "Revpy" yet, so this is a clean revert.

**IMPORTANT:** Only revert the Revpy→Revclip rename. Do NOT revert other feature changes made in v0.0.13/v0.0.14 (template editor, icon-only toggle, folder spacing, hotkey, menu text length, snippet tooltips).

## What to Revert

### 1. All source files (.m and .h) — copyright headers
Every .m and .h file under `src/Revclip/Revclip/` was changed from:
```
// Revclip
// Copyright (c) 2024-2026 Revclip. All rights reserved.
```
to:
```
// Revpy
// Copyright (c) 2024-2026 Revpy. All rights reserved.
```

**Revert ALL back to "Revclip".**

Use `grep -rl "Revpy" src/Revclip/Revclip/` to find all files, then replace "Revpy" → "Revclip" in the copyright headers.

### 2. Info.plist (`src/Revclip/Revclip/Info.plist`)
- CFBundleName: "Revpy" → "Revclip"
- CFBundleDisplayName: "Revpy" → "Revclip"
- NSAccessibilityUsageDescription: "Revpy needs..." → "Revclip needs..."
- NSHumanReadableCopyright: "Revpy" → "Revclip"

### 3. project.yml (`src/Revclip/project.yml`)
- CFBundleName: "Revpy" → "Revclip"
- CFBundleDisplayName: "Revpy" → "Revclip"
- NSHumanReadableCopyright: "Revpy" → "Revclip"
- NSAccessibilityUsageDescription: "Revpy" → "Revclip"
- **Remove** `PRODUCT_NAME: Revpy` (just delete that line entirely — it defaults to the target name "Revclip")
- TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Revpy.app/Contents/MacOS/Revpy" → "$(BUILT_PRODUCTS_DIR)/Revclip.app/Contents/MacOS/Revclip"

### 4. InfoPlist.strings (all 5 languages)
- "Copyright © 2024-2026 Revpy" → "Copyright © 2024-2026 Revclip"

### 5. Localizable.strings (all 5 languages)
- Any "Revpy" references → "Revclip"
- Check "Quit Revpy" → "Quit Revclip" and any other occurrences

### 6. MainMenu.xib and MainMenu.strings (all 5 languages)
- "Revpy" → "Revclip" everywhere (About, Quit, Hide, etc.)

### 7. Source code user-facing strings
- `RCMenuManager.m`: menu titles, accessibility descriptions — "Revpy" → "Revclip"
- `RCAccessibilityService.m`: alert strings — "Revpy" → "Revclip"
- `RCMoveToApplicationsService.m`: alert strings, fallback names — "Revpy" → "Revclip", "Revpy.app" → "Revclip.app"
- `RCPrivacyService.m`: alert strings — "Revpy" → "Revclip"
- `RCAppDelegate.m`: NSLog prefix — "[Revpy]" → "[Revclip]"
- `RCSnippetEditorWindowController.m`: NSLog prefixes — "[Revpy]" → "[Revclip]"

### 8. CI workflow (`.github/workflows/release.yml`)
- "Revpy.app" → "Revclip.app" (3 occurrences)
- "Revpy-${GITHUB_REF_NAME}.dmg" → "Revclip-${GITHUB_REF_NAME}.dmg"
- `-volname "Revpy"` → `-volname "Revclip"`

## Verification Strategy

After all changes, verify NO "Revpy" remains:
```bash
grep -r "Revpy" src/Revclip/ .github/ --include="*.m" --include="*.h" --include="*.strings" --include="*.xib" --include="*.plist" --include="*.yml" | grep -v ".claude/" | grep -v ".agent/"
```
This should return ZERO results.

Then build:
```bash
cd src/Revclip && xcodegen generate && xcodebuild -scheme Revclip -configuration Debug build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

Must succeed with `** BUILD SUCCEEDED **`.

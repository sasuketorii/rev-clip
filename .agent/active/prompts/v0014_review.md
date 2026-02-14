# Reviewer Task: v0.0.14 — 3 Fixes Review

Evaluate the diff against these 3 requirements.

## Issue 1: App bundle name "Revclip.app" → "Revpy.app"
- PRODUCT_NAME: Revpy added to project.yml base settings
- TEST_HOST updated to reference Revpy.app/Contents/MacOS/Revpy
- Bundle identifier UNCHANGED (com.revclip.Revclip) — correct for backwards compat

## Issue 2: Clipboard history text too short (20 chars → 40 chars)
- Default max title length changed from 20 to 40 in:
  - RCMenuManager.m (menuTitleForClipItem:globalIndex:)
  - RCUtilities.m (registerDefaults)
  - RCConstants.h (comment)

## Issue 3: Template/snippet menu items show content tooltip on hover
- toolTip set on snippet menu items with first 200 chars of content
- Only set when content is non-empty

## Build Verification
Run: `cd src/Revclip && xcodegen generate && xcodebuild -scheme Revclip -configuration Debug build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`

## Output
If all issues fixed correctly: `LGTM`
If problems found: `FINDING: [severity] [issue#] description`

## Diff


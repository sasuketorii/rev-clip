# Fix Task: MainMenu.xib and MainMenu.strings — Revclip → Revpy

## Permissions
- Main branch OK. No worktree/branch needed.
- You may edit any file under `src/Revclip/`.

## Issue
The reviewer found that `MainMenu.xib` and `MainMenu.strings` (5 languages) still contain "Revclip" references that need to be changed to "Revpy".

## Files to Fix

### 1. MainMenu.xib
- File: `src/Revclip/Revclip/Resources/MainMenu.xib`
- Change ALL occurrences of "Revclip" to "Revpy" in user-facing strings (menu titles, about text, etc.)
- Look for: "About Revclip", "Quit Revclip", "Hide Revclip", or any other "Revclip" references

### 2. MainMenu.strings (all 5 languages)
- `src/Revclip/Revclip/Resources/en.lproj/MainMenu.strings`
- `src/Revclip/Revclip/Resources/ja.lproj/MainMenu.strings`
- `src/Revclip/Revclip/Resources/de.lproj/MainMenu.strings`
- `src/Revclip/Revclip/Resources/zh-Hans.lproj/MainMenu.strings`
- `src/Revclip/Revclip/Resources/it.lproj/MainMenu.strings`
- Change ALL occurrences of "Revclip" to "Revpy" in the VALUES (right side of `=`).
- Do NOT change the KEYS (left side of `=`) as they reference XIB object IDs.

## Build Verification
After changes, run:
```bash
cd src/Revclip && xcodegen generate && xcodebuild -scheme Revclip -configuration Debug build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

Must succeed with `** BUILD SUCCEEDED **`.

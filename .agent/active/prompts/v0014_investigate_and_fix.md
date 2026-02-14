# Coder Task: v0.0.14 — 3 Fixes

## Permissions
- Main branch OK. No worktree/branch needed.
- You may edit any file under `src/Revclip/`.

## Project Info
- macOS Objective-C app (no Swift)
- Build: `cd src/Revclip && xcodegen generate && xcodebuild -scheme Revclip -configuration Debug build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`
- XcodeGen project: `src/Revclip/project.yml`

---

## Issue 1: App bundle name still shows "Revclip" in Finder

The display name (CFBundleName/CFBundleDisplayName) was changed to "Revpy" in v0.0.13, but the actual .app bundle file is still named "Revclip.app" in /Applications. This is because the Xcode target name is "Revclip" and PRODUCT_NAME defaults to the target name.

### Fix:
In `src/Revclip/project.yml`, add `PRODUCT_NAME: Revpy` to the base build settings:

```yaml
    settings:
      base:
        PRODUCT_NAME: Revpy
        PRODUCT_BUNDLE_IDENTIFIER: com.revclip.Revclip
        ...
```

This will make the output .app bundle "Revpy.app" without changing the target name or bundle identifier.

**Also** update `RCMoveToApplicationsService.m`:
- The fallback `bundleBaseName = @"Revpy"` (already done in v0.0.13)
- The fallback `bundleName = @"Revpy.app"` (already done in v0.0.13)

**Also** check `RevclipTests` target in project.yml — its `TEST_HOST` path references `Revclip.app`:
```yaml
TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Revclip.app/Contents/MacOS/Revclip"
```
This needs to be updated to match the new PRODUCT_NAME:
```yaml
TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Revpy.app/Contents/MacOS/Revpy"
```

---

## Issue 2: Clipboard history menu item text too short on hover

When hovering over a clipboard history menu item, the text is truncated to ~20 characters (e.g., "# 指示文 あなたはオーケストレー...").

The max length is controlled by `kRCPrefMaxMenuItemTitleLengthKey` with a default value of 20 in `RCMenuManager.m` method `menuTitleForClipItem:globalIndex:`.

### Fix:
1. Find where the default value of 20 is used for `kRCPrefMaxMenuItemTitleLengthKey` and change it to **40**.
2. The line should look like: `[self integerPreferenceForKey:kRCPrefMaxMenuItemTitleLengthKey defaultValue:20]` → change `20` to `40`.

---

## Issue 3: Template/snippet menu items don't show content on hover

When hovering over a snippet/template sub-menu item (e.g., "frontend" under "orchestrator_prompt" folder), no tooltip is shown with the snippet content.

### Investigation needed:
1. Find how snippet/template menu items are created in `RCMenuManager.m`. Look for methods that build the snippet sub-menus (different from the clipboard history items).
2. Find where individual snippet NSMenuItem objects are created.

### Fix:
For each snippet menu item, set `item.toolTip` to a preview of the snippet content (first ~200 characters, or the full content if shorter). This lets users see the snippet content on hover without clicking.

Look for the method that creates snippet menu items and add:
```objc
item.toolTip = [snippetContent length] > 200
    ? [[snippetContent substringToIndex:200] stringByAppendingString:@"..."]
    : snippetContent;
```

---

## Build Verification

After ALL changes, run:
```bash
cd src/Revclip && xcodegen generate && xcodebuild -scheme Revclip -configuration Debug build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

Must succeed with `** BUILD SUCCEEDED **`.

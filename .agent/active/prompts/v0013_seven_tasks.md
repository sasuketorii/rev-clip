# Coder Task: v0.0.13 — 7 Feature Changes

## Permissions
- Main branch OK. No worktree/branch needed.
- You may edit any file under `src/Revclip/`.

## Project Info
- macOS Objective-C app (no Swift)
- Build: `cd src/Revclip && xcodegen generate && xcodebuild -scheme Revclip -configuration Debug build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`
- 5 localization languages: en, ja, de, zh-Hans, it
- Localizable.strings use English keys as NSLocalizedString lookup keys

---

## Task 1: Rename "Snippet Editor" → "Template Editor"

### Source code changes:
1. `src/Revclip/Revclip/UI/SnippetEditor/RCSnippetEditorWindowController.m` line ~136:
   - `NSLocalizedString(@"Snippet Editor", nil)` → `NSLocalizedString(@"Template Editor", nil)`

2. `src/Revclip/Revclip/Managers/RCMenuManager.m` line ~530:
   - `NSLocalizedString(@"Edit Snippets...", nil)` → `NSLocalizedString(@"Edit Templates...", nil)`

3. `src/Revclip/Revclip/UI/SnippetEditor/RCSnippetEditorWindow.xib` line ~15:
   - `title="スニペットエディタ"` → `title="テンプレートエディタ"`

### Localizable.strings changes (ALL 5 languages):
- Remove old key `"Snippet Editor"` and add `"Template Editor"` with appropriate translations
- Remove old key `"Edit Snippets..."` and add `"Edit Templates..."` with appropriate translations

Translations:
| Key | en | ja | de | zh-Hans | it |
|-----|----|----|----|---------|----|
| Template Editor | Template Editor | テンプレートエディタ | Vorlageneditor | 模板编辑器 | Editor modelli |
| Edit Templates... | Edit Templates... | テンプレートを編集... | Vorlagen bearbeiten... | 编辑模板... | Modifica modelli... |

---

## Task 2: Enable/Disable Toggle — Icon Only (Remove Text)

File: `src/Revclip/Revclip/UI/SnippetEditor/RCSnippetEditorWindowController.m`

Current code (~line 318-321):
```objc
self.enabledToggleButton = [self actionButtonWithTitle:NSLocalizedString(@"Enable/Disable", nil)
                                             symbolName:@"eye"
                                                 action:@selector(toggleSelectedItemEnabled:)];
```

Changes:
1. Create the button with an EMPTY title `@""` instead of the localized string, but keep the symbolName for the icon.
2. After creating the button, set `button.imagePosition = NSImageOnly;` to display only the icon.
3. Reduce the width constraint from `124.0` (line ~353) to `36.0` to fit just the icon.
4. Set a tooltip on the button: `self.enabledToggleButton.toolTip = NSLocalizedString(@"Enable/Disable", nil);`
5. Keep the "Enable/Disable" key in Localizable.strings (used for tooltip now).

---

## Task 3: Add Vertical Spacing Between Folder Groups in Sidebar

File: `src/Revclip/Revclip/UI/SnippetEditor/RCSnippetEditorWindowController.m`

The outline view currently uses the same row height for folders and snippets, making it hard to distinguish them.

Add this NSOutlineView delegate method:
```objc
- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item {
    if ([item isKindOfClass:[RCSnippetFolderNode class]]) {
        NSInteger row = [outlineView rowForItem:item];
        if (row > 0) {
            return 30.0;  // Taller row for non-first folders (adds top spacing)
        }
    }
    return 22.0;  // Default height
}
```

Also, in `outlineView:viewForTableColumn:item:`, for folder cells that have extra height (row > 0), vertically align the text to the BOTTOM of the cell instead of center. This creates visual top margin above the folder name.

Implementation approach:
- Use two different cell identifiers: `RCSnippetEditorCell` for normal rows and `RCSnippetEditorFolderSpacedCell` for folder rows with spacing
- For the spaced folder cell, constrain the text field's bottomAnchor to `cell.bottomAnchor` with constant `-4.0` (instead of centerYAnchor)

---

## Task 4: Change Default Hotkey from Ctrl+Shift+V to Cmd+Shift+V

Two files to change:

1. `src/Revclip/Revclip/Services/RCHotKeyService.m` line ~333:
   - `mainCombo = RCMakeKeyCombo(kRCKeyCodeV, controlKey | shiftKey);`
   - → `mainCombo = RCMakeKeyCombo(kRCKeyCodeV, cmdKey | shiftKey);`

2. `src/Revclip/Revclip/UI/Preferences/RCShortcutsPreferencesViewController.m` line ~148:
   - `return RCMakeKeyCombo(kRCDefaultKeyCodeV, controlKey | shiftKey);`
   - → `return RCMakeKeyCombo(kRCDefaultKeyCodeV, cmdKey | shiftKey);`

---

## Task 5: Align Title Field Padding with Content Text View

File: `src/Revclip/Revclip/UI/SnippetEditor/RCSnippetEditorWindowController.m`

Both the title NSTextField and content NSScrollView use a leading constraint of `inset` (16.0pt). However, NSTextField has built-in internal cell padding (~2-3pt), while NSTextView's text starts at the edge of its container.

Fix: Reduce the titleField's leading constraint by 3pt so the text visually aligns with the content text view's text.

Change (in the constraint block around line ~271):
```objc
// Before:
[self.titleField.leadingAnchor constraintEqualToAnchor:rightPane.leadingAnchor constant:inset],
[self.titleField.trailingAnchor constraintEqualToAnchor:rightPane.trailingAnchor constant:-inset],

// After:
[self.titleField.leadingAnchor constraintEqualToAnchor:rightPane.leadingAnchor constant:inset - 3.0],
[self.titleField.trailingAnchor constraintEqualToAnchor:rightPane.trailingAnchor constant:-(inset - 3.0)],
```

Also verify: check if the NSTextView inside contentScrollView has `textContainerInset`. If it does, that affects alignment too. Adjust the offset accordingly to make the TEXT visually start at the same x-position in both fields.

---

## Task 6: Clipboard History — Number Always First

File: `src/Revclip/Revclip/Managers/RCMenuManager.m`

Currently, NSMenuItem uses `item.image` (rendered LEFT of title by macOS) + `item.title` = `"%ld. %@"`.
Result: `[icon] 1. text text`

User wants: `1. [icon] text text` — number ALWAYS first.

### Implementation:

Modify `clipMenuItemForClipItem:globalIndex:` method (~line 596-685):

1. Build the title string as before (with number prefix if enabled).
2. Instead of setting `item.image`, create an `NSAttributedString` with:
   - The number + ". " as plain text (e.g., "1. ")
   - An `NSTextAttachment` containing the image (icon/thumbnail)
   - A space + the remaining title text
3. Set `item.attributedTitle = attrTitle;`
4. Set `item.image = nil;` (don't let macOS render image before title)

For the NSTextAttachment image sizing:
- For small type icons (16x16): use `attachment.bounds = CGRectMake(0, -2, 16, 16);`
- For thumbnails/image previews: resize to a reasonable menu size, e.g., `CGRectMake(0, -10, 40, 40)` or whatever the current thumbnail size is. Check the existing code for the image size being set.

When numbering is DISABLED (`shouldPrefixIndex == NO`):
- Still use `item.image` as before (no attributed string needed), OR
- Use attributed string without the number prefix: `[icon attachment] text`

### Key considerations:
- The attributed string must inherit the system menu font (use `[NSFont menuFontOfSize:0]` for default)
- For items without an image, just use the plain title (no attachment)
- Make sure the attachment vertical alignment (`bounds.origin.y`) looks correct in the menu

---

## Task 7: Service Name Change — Revclip → Revpy

### User-facing strings to change:

1. **Info.plist** (`src/Revclip/Revclip/Info.plist`):
   - CFBundleName: "Revclip" → "Revpy"
   - CFBundleDisplayName: "Revclip" → "Revpy"
   - NSAccessibilityUsageDescription: "Revclip needs..." → "Revpy needs..."
   - NSHumanReadableCopyright: "Revclip" → "Revpy"

2. **project.yml** (`src/Revclip/project.yml`):
   - CFBundleName: "Revclip" → "Revpy"
   - CFBundleDisplayName: "Revclip" → "Revpy"
   - NSHumanReadableCopyright: "Revclip" → "Revpy"
   - NSAccessibilityUsageDescription: "Revclip" → "Revpy"

3. **InfoPlist.strings** (all 5 languages):
   - "Copyright © 2024-2026 Revclip. All rights reserved." → "Copyright © 2024-2026 Revpy. All rights reserved."

4. **Localizable.strings** (all 5 languages):
   - "Quit Revclip" key/value → "Quit Revpy" (check if this key exists; if so update)
   - Any other "Revclip" references

5. **RCMenuManager.m**:
   - Line ~68: `[self menuWithTitle:@"Revclip"]` → `@"Revpy"`
   - Line ~230: `accessibilityDescription:@"Revclip"` → `@"Revpy"`
   - Line ~359: `[self menuWithTitle:@"Revclip"]` → `@"Revpy"`
   - Line ~536: `NSLocalizedString(@"Quit Revclip", nil)` → `NSLocalizedString(@"Quit Revpy", nil)`

6. **RCAccessibilityService.m**:
   - Line ~59-60: "Revclip requires..." → "Revpy requires...", "Revclip needs..." → "Revpy needs..."

7. **RCMoveToApplicationsService.m**:
   - Line ~61: "Revclip needs to be..." → "Revpy needs to be..."
   - Line ~189-190: "Could not move Revclip..." → "Could not move Revpy...", "...moving Revclip" → "...moving Revpy"
   - Line ~94: `bundleBaseName = @"Revclip"` → `@"Revpy"`
   - Line ~198: `bundleName = @"Revclip.app"` → `@"Revpy.app"`

8. **RCPrivacyService.m**:
   - Line ~147-148: "Revclip needs clipboard access" → "Revpy needs clipboard access", "...allow Revclip to access..." → "...allow Revpy to access..."

9. **RCAppDelegate.m**:
   - Line ~100: `NSLog(@"[Revclip]..."` → `NSLog(@"[Revpy]..."`
   - Line ~32: Check `revclipsnippets` file extension — KEEP AS IS (backwards compat)
   - Line ~182: Keep `snippets.revclipsnippets` AS IS

10. **RCSnippetEditorWindowController.m**:
    - NSLog messages: `[Revclip]` → `[Revpy]`

11. **All .m and .h files under src/Revclip/Revclip/**:
    - Copyright comment header: `// Revclip` → `// Revpy`
    - `// Copyright (c) 2024-2026 Revclip. All rights reserved.` → `// Copyright (c) 2024-2026 Revpy. All rights reserved.`

### DO NOT CHANGE (backwards compatibility):
- Bundle identifier: `com.revclip.Revclip` — KEEP
- Application Support paths: `~/Library/Application Support/Revclip/` — KEEP
- File extension: `.revclipsnippets` — KEEP
- Sparkle feed URL — KEEP
- Pasteboard drag type: `com.revclip.snippet-outline-item` — KEEP
- Error domain strings: `com.revclip.*` — KEEP
- Dispatch queue names: `com.revclip.*` — KEEP
- Database format identifier: `revclip.snippets` — KEEP
- Directory/file names on disk — KEEP
- Target name in project.yml — KEEP
- Class name prefixes (RC*) — KEEP
- NSUserDefaults keys — KEEP

---

## Build Verification

After ALL changes, run:
```bash
cd src/Revclip && xcodegen generate && xcodebuild -scheme Revclip -configuration Debug build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

The build MUST succeed with `** BUILD SUCCEEDED **`.

---

## Summary of Files to Modify

| File | Tasks |
|------|-------|
| RCSnippetEditorWindowController.m | 1, 2, 3, 5, 7 |
| RCMenuManager.m | 1, 6, 7 |
| RCHotKeyService.m | 4 |
| RCShortcutsPreferencesViewController.m | 4 |
| RCSnippetEditorWindow.xib | 1 |
| Info.plist | 7 |
| project.yml | 7 |
| All Localizable.strings (5 langs) | 1, 7 |
| All InfoPlist.strings (5 langs) | 7 |
| RCAccessibilityService.m | 7 |
| RCMoveToApplicationsService.m | 7 |
| RCPrivacyService.m | 7 |
| RCAppDelegate.m | 7 |
| All other .m/.h files | 7 (comment headers only) |

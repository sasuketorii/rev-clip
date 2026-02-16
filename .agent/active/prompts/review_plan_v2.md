# Plan Review Request (Rev.2)

## Role
You are a senior software architect reviewing an implementation plan for a macOS clipboard manager app (Revclip).
The app is written in Objective-C, uses FMDB (SQLite), Sparkle (auto-update), and runs as a menu bar app.

## Task
This is a **re-review** of a plan that was revised based on your previous 10 findings.
Review the attached ExecPlan Rev.2 and verify that all previous findings have been properly addressed.

### Previous Findings That Should Be Fixed:
1. **Critical**: Phase 1-2 screenshot JPEG replacing TIFF data → should be thumbnail-only
2. **High**: Phase 3 Panic missing queue drain / write prohibition flag
3. **High**: Phase 3-4 Panic hotkey should be in Shortcuts prefs, not General
4. **Medium**: Phase 3-1 NSUserDefaults reset order (save to local vars first)
5. **Medium**: Phase 1-3 Screenshot monitor missing debounce cleanup trigger
6. **Medium**: Phase 2-3 Service-layer clamp for auto-expiry settings
7. **Medium**: Phase 4-1 Missing startup permission repair for existing files
8. **Medium**: Phase 4-2 auto_vacuum migration for existing DBs
9. **Low**: Phase 4-3 Unspecified call location for TM/Spotlight exclusion
10. **Nit**: project.yml may not need changes

## Output Format

### Review Verdict: LGTM / NEEDS_CHANGES

### Previous Findings Status
For each of the 10 previous findings:
- **Finding N**: RESOLVED / PARTIALLY_RESOLVED / NOT_RESOLVED — brief note

### New Findings (if any)
For each new finding:
- **Severity**: Critical / High / Medium / Low / Nit
- **Location**: Which section of the plan
- **Issue**: What's wrong
- **Suggestion**: How to fix it

### Overall Assessment
Brief summary of plan quality after revision.

## Review Criteria
1. **Completeness**: Are all necessary files identified? Are there missing changes?
2. **Correctness**: Are the proposed APIs/signatures appropriate for Objective-C/Cocoa?
3. **Feasibility**: Can each phase be implemented without breaking existing functionality?
4. **Ordering**: Are dependencies between phases correctly identified?
5. **Edge Cases**: Are edge cases properly addressed?
6. **Security**: Are the security measures sufficient for the stated goals?
7. **Consistency**: Is the plan internally consistent (no contradictions)?

## Context Files
Read the following files to understand the codebase context:
- `src/Revclip/Revclip/App/RCConstants.h`
- `src/Revclip/Revclip/App/RCConstants.m`
- `src/Revclip/Revclip/Services/RCDataCleanService.m`
- `src/Revclip/Revclip/Services/RCClipboardService.m`
- `src/Revclip/Revclip/Services/RCScreenshotMonitorService.m`
- `src/Revclip/Revclip/Managers/RCDatabaseManager.h`
- `src/Revclip/Revclip/Managers/RCDatabaseManager.m`
- `src/Revclip/Revclip/Managers/RCMenuManager.m`
- `src/Revclip/Revclip/Services/RCHotKeyService.m`
- `src/Revclip/Revclip/Models/RCClipData.m`
- `src/Revclip/Revclip/UI/Preferences/RCGeneralPreferencesViewController.m`
- `src/Revclip/Revclip/UI/Preferences/RCShortcutsPreferencesViewController.m`
- `src/Revclip/Revclip/Services/RCSnippetImportExportService.m`
- `src/Revclip/Revclip/Utilities/RCUtilities.m`
- `src/Revclip/Revclip/App/RCAppDelegate.m`

## Important Notes
- The app currently works perfectly with no known bugs
- Existing behavior must NOT be broken
- Items under "スコープ外" should remain excluded
- Focus on practical implementability

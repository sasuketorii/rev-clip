# Investigation: Auto-Expiry Feature Design

## Role
You are a macOS application architect. Design an auto-expiry feature for the Revclip clipboard manager that allows users to automatically delete old clipboard history.

## Context
The user wants to add a settings UI where they can configure automatic deletion of old clipboard items.

### Current State
Read these files to understand the current architecture:
- `src/Revclip/Revclip/Services/RCDataCleanService.m` - Current cleanup logic
- `src/Revclip/Revclip/Managers/RCDatabaseManager.h` / `.m` - Database operations (note: deleteClipItemsOlderThan: already exists!)
- `src/Revclip/Revclip/App/RCConstants.h` / `.m` - Current preference keys
- `src/Revclip/Revclip/Utilities/RCUtilities.m` - Default settings
- `src/Revclip/Revclip/UI/Preferences/RCGeneralPreferencesViewController.m` - General preferences UI
- `src/Revclip/Revclip/Services/RCClipboardService.m` - Clipboard service

## Feature Requirements

### User Settings
- Unit selector: Day / Hour / Minute
- Number input: How many units (e.g., "7 days", "24 hours", "30 minutes")
- All items older than the configured time should be automatically deleted
- Default: Disabled (no auto-expiry)

### Technical Requirements
1. New preference keys needed
2. Integration with RCDataCleanService (existing 30-min cleanup timer can be leveraged)
3. File deletion must accompany database deletion (both .rcclip and .thumbnail files)
4. The feature should be consistent with existing kRCPrefMaxHistorySizeKey (both limits apply: whichever is more restrictive wins)

## Analysis Required
1. **Existing infrastructure**: What already exists that can be reused? (e.g., deleteClipItemsOlderThan: method)
2. **New code needed**: What new code/methods/UI elements would be needed?
3. **Preference storage**: How should the expiry settings be stored in NSUserDefaults?
4. **UI design**: What UI elements should be added to the General preferences tab?
5. **Edge cases**: What happens when the setting is changed? Should it immediately purge old items?
6. **Migration**: How to handle existing users who update to this version?

## Output Format
Provide a detailed technical design document in Japanese with:
1. Architecture overview
2. New preference keys and their defaults
3. Code changes needed (which files, what methods)
4. UI mockup description
5. Implementation priority and suggested approach
6. Interaction with existing maxHistorySize setting

Output in Japanese (technical terms in English are OK).

# Investigation: Secure Deletion & Panic Button Feature

## Role
You are a macOS security engineer specializing in data sanitization and anti-forensics. Design secure deletion and panic button features for the Revclip clipboard manager.

## Context
The user has two related requirements:
1. **Secure Deletion**: Completely delete history without going through macOS Trash. Current deletion uses NSFileManager removeItemAtPath: which just unlinks files.
2. **Panic Button**: A single-action button that immediately and irreversibly destroys ALL history data AND all snippet/template data, leaving zero forensic trace. The user explicitly mentions this is for situations like "tax audits" where even minor evidence must be eliminated.

## Target Files
Read ALL of these files to understand current deletion mechanisms:
- `src/Revclip/Revclip/Services/RCDataCleanService.m` - Current cleanup/deletion logic
- `src/Revclip/Revclip/Services/RCClipboardService.m` - deleteFileAtPath: / deleteFilesForClipItem:
- `src/Revclip/Revclip/Managers/RCDatabaseManager.h` / `.m` - deleteAllClipItems, deleteClipItemWithDataHash, deleteAllSnippetFolders
- `src/Revclip/Revclip/Models/RCClipData.m` - File I/O
- `src/Revclip/Revclip/Utilities/RCUtilities.m` - Directory paths
- `src/Revclip/Revclip/App/RCConstants.h` / `.m` - Data paths
- `src/Revclip/Revclip/Services/RCSnippetImportExportService.m` - Snippet data

## Investigation Areas

### 1. Current Deletion Behavior
- How does NSFileManager removeItemAtPath: work? Does it bypass Trash? (Yes, it does bypass Trash)
- Is data actually overwritten on disk or just unlinked from the filesystem?
- APFS behavior: Does APFS copy-on-write mean deleted data remains recoverable?
- SQLite DELETE: Does it actually zero out the data pages or just mark them as free?

### 2. Secure File Deletion on macOS
- On APFS (all modern Macs): `srm` (secure remove) was removed by Apple. What alternatives exist?
- Can we overwrite file contents before deletion? (write zeros/random data to the file before unlinking)
- Does NSFileManager provide secure deletion options?
- What about SSD TRIM behavior - does it make overwriting pointless?
- Encryption-based approach: Could we encrypt data at rest and destroy the key for secure deletion?

### 3. SQLite Secure Deletion
- PRAGMA secure_delete = ON - does this help?
- SQLite VACUUM after DELETE - does this reclaim space?
- Can we drop tables and recreate them?
- Should we delete the entire .db file and recreate from scratch?

### 4. Forensic Considerations
- NSUserDefaults (plist): History-related preferences might leak info
- macOS Unified Logging: NSLog calls might contain data
- Spotlight index: .rcclip files might be indexed
- Time Machine: ~/Library/Application Support/Revclip/ in backups
- APFS snapshots: Can contain old versions of files
- Swap/VM: In-memory clipboard data written to swap
- Crash reports: Might contain clipboard data

### 5. Panic Button Design
- Should it have a confirmation dialog or be instant? (Consider accidental presses vs speed requirement)
- Should it be a hotkey, menu item, or settings button?
- What should the sequence be?
  1. Stop clipboard monitoring immediately
  2. Overwrite all .rcclip files with zeros
  3. Overwrite all .thumbnail.tiff files with zeros
  4. DELETE all rows from SQLite tables
  5. VACUUM the database
  6. Optionally delete the entire database file
  7. Clear NSUserDefaults of any potentially sensitive keys
  8. Clear any in-memory caches
  9. Optionally quit the application

### 6. Implementation Feasibility
- Performance: How long would secure deletion of 100 files take?
- Can we do it asynchronously or must it be synchronous (panic = immediate)?
- What's the minimum viable implementation vs the gold standard?

## Output Format
Provide a comprehensive technical analysis in Japanese with:
1. Current deletion behavior analysis
2. Secure deletion techniques applicable to macOS APFS
3. SQLite secure deletion strategy
4. Forensic trace elimination checklist
5. Panic button UX design
6. Technical implementation plan with code structure
7. Limitations and caveats (what CAN'T be securely deleted on modern macOS)
8. Priority-ordered implementation recommendations

Output in Japanese (technical terms in English are OK).

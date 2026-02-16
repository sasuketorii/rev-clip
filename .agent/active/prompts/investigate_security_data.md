# Security Audit: Data Security & Privacy

## Role
You are a macOS data security specialist. Analyze the Revclip clipboard manager for data leakage, privacy, and file system security issues.

## Target Files
Read and analyze ALL of the following files:
- `src/Revclip/Revclip/Models/RCClipData.h` / `.m`
- `src/Revclip/Revclip/Models/RCClipItem.h` / `.m`
- `src/Revclip/Revclip/Managers/RCDatabaseManager.h` / `.m`
- `src/Revclip/Revclip/Services/RCClipboardService.m`
- `src/Revclip/Revclip/Services/RCDataCleanService.m`
- `src/Revclip/Revclip/Services/RCPrivacyService.m`
- `src/Revclip/Revclip/Services/RCScreenshotMonitorService.m`
- `src/Revclip/Revclip/Services/RCSnippetImportExportService.m`
- `src/Revclip/Revclip/Utilities/RCUtilities.m`
- `src/Revclip/Revclip/App/RCConstants.h` / `.m`
- `src/Revclip/Revclip/Revclip.entitlements`

## Investigation Areas
1. **Data at Rest Encryption** - Is the SQLite database encrypted? Are .rcclip files encrypted? Are thumbnail files encrypted?
2. **File Permissions** - Are data files created with appropriate POSIX permissions? Can other apps read them?
3. **NSSecureCoding** - Is the NSKeyedArchiver usage secure against deserialization attacks?
4. **Sensitive Data Logging** - Are clipboard contents logged via NSLog? Could sensitive data leak to Console.app or syslog?
5. **Data Remnants** - After deletion, are data files actually overwritten or just unlinked? Could forensic tools recover deleted clipboard data?
6. **macOS Privacy** - org.nspasteboard.ConcealedType handling. Are password manager entries properly skipped?
7. **Spotlight Indexing** - Are .rcclip files indexed by Spotlight? Could clipboard data appear in Spotlight searches?
8. **Time Machine** - Are clipboard data files backed up by Time Machine? Privacy concern.
9. **iCloud Sync** - Is ~/Library/Application Support/Revclip/ synced to iCloud?
10. **Crash Reports** - kRCCollectCrashReport setting. Could crash logs contain clipboard data?
11. **Memory Disclosure** - Are NSData objects containing sensitive clipboard data properly zeroed after use?
12. **Path Traversal** - Can crafted data_path or thumbnail_path values escape the ClipsData directory?

## Output Format
For each finding, provide:
- **Severity**: Critical / High / Medium / Low / Info
- **Location**: File and line number
- **Description**: What the vulnerability is
- **Risk**: What could happen if exploited
- **Recommendation**: How to fix it

Output in Japanese (technical terms in English are OK).

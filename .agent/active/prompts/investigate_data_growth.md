# Investigation: Clipboard Data Growth Analysis

## Role
You are a macOS application performance/storage analyst. Investigate whether the Revclip clipboard manager has unbounded data growth issues.

## Target Files
Read and analyze ALL of the following files:
- `src/Revclip/Revclip/Services/RCClipboardService.m`
- `src/Revclip/Revclip/Services/RCDataCleanService.m`
- `src/Revclip/Revclip/Services/RCScreenshotMonitorService.m`
- `src/Revclip/Revclip/Managers/RCDatabaseManager.h` / `.m`
- `src/Revclip/Revclip/Models/RCClipData.h` / `.m`
- `src/Revclip/Revclip/Models/RCClipItem.h` / `.m`
- `src/Revclip/Revclip/Utilities/RCUtilities.m`
- `src/Revclip/Revclip/App/RCConstants.h` / `.m`

## Investigation Questions

### 1. Current Trimming Mechanism
- What is the current max history size? (kRCPrefMaxHistorySizeKey = 30)
- How does RCDataCleanService.trimHistoryIfNeededWithDatabaseManager work?
- When is cleanup triggered? (kRCCleanupInterval = 30 min)
- Does orphan file cleanup work correctly?

### 2. Growth Vectors
- **Large images**: If a user copies a 100MB image, how is it stored? Is there a size limit per clip item?
- **TIFF data**: TIFFData can be very large. Is there a max size?
- **Screenshot monitoring**: RCScreenshotMonitorService stores full TIFF data of screenshots. High-resolution screenshots can be 20-50MB each.
- **Between cleanup intervals**: In the 30-min window between cleanups, how many clips could accumulate?
- **Polling frequency**: 0.5 second polling interval means lots of potential captures.

### 3. Database Growth
- Is the SQLite database vacuumed after deletions?
- Do SQLite WAL/journal files grow unboundedly?
- Is there a maximum database file size?

### 4. File System Growth
- ClipsData directory: .rcclip files + .thumbnail.tiff files
- What happens if a user copies very large files (file paths stored, but what about RTFD data with embedded images)?
- Is there any total storage size cap?

### 5. Worst Case Scenarios
- Calculate: User copies a 50MB image every minute for a day. What's the peak storage usage before cleanup?
- What if kRCPrefMaxHistorySizeKey is set to a very large number (e.g., 999999)?
- What if cleanup timer fails to fire?

## Output Format
Provide a detailed analysis in Japanese with:
1. Current state summary
2. Identified growth risks (with severity)
3. Specific recommendations for mitigating each risk
4. Suggested implementation approach for size-based limits

Output in Japanese (technical terms in English are OK).

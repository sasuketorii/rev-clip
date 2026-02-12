//
//  RCConstants.h
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// General
extern NSString * const kRCPrefMaxHistorySizeKey;              // Default: 30
extern NSString * const kRCPrefInputPasteCommandKey;           // Default: YES
extern NSString * const kRCPrefReorderClipsAfterPasting;       // Default: YES
extern NSString * const kRCPrefShowStatusItemKey;              // Default: 1 (black)
extern NSString * const kRCPrefStoreTypesKey;                  // Default: all types YES
extern NSString * const kRCPrefOverwriteSameHistory;           // Default: YES
extern NSString * const kRCPrefCopySameHistory;                // Default: YES
extern NSString * const kRCCollectCrashReport;                 // Default: YES
extern NSString * const loginItem;                             // Default: NO
extern NSString * const suppressAlertForLoginItem;             // Default: NO

// Menu
extern NSString * const kRCPrefNumberOfItemsPlaceInlineKey;        // Default: 0
extern NSString * const kRCPrefNumberOfItemsPlaceInsideFolderKey;  // Default: 10
extern NSString * const kRCPrefMaxMenuItemTitleLengthKey;          // Default: 20
extern NSString * const kRCPrefMenuIconSizeKey;                    // Default: 16
extern NSString * const kRCPrefShowIconInTheMenuKey;               // Default: YES
extern NSString * const kRCMenuItemsAreMarkedWithNumbersKey;       // Default: YES
extern NSString * const kRCPrefMenuItemsTitleStartWithZeroKey;     // Default: NO
extern NSString * const kRCShowToolTipOnMenuItemKey;               // Default: YES
extern NSString * const kRCMaxLengthOfToolTipKey;                  // Default: 200
extern NSString * const kRCShowImageInTheMenuKey;                  // Default: YES
extern NSString * const kRCPrefShowColorPreviewInTheMenu;          // Default: YES
extern NSString * const kRCAddNumericKeyEquivalentsKey;            // Default: NO
extern NSString * const kRCThumbnailWidthKey;                      // Default: 100
extern NSString * const kRCThumbnailHeightKey;                     // Default: 32
extern NSString * const kRCPrefAddClearHistoryMenuItemKey;         // Default: YES
extern NSString * const kRCPrefShowAlertBeforeClearHistoryKey;     // Default: YES

// Shortcuts
extern NSString * const kRCHotKeyMainKeyCombo;
extern NSString * const kRCHotKeyHistoryKeyCombo;
extern NSString * const kRCHotKeySnippetKeyCombo;
extern NSString * const kRCClearHistoryKeyCombo;
extern NSString * const kRCFolderKeyCombos;
extern NSString * const kRCMigrateNewKeyCombo;
extern NSString * const kRCPrefHotKeysKey;

// Updates
extern NSString * const kRCEnableAutomaticCheckKey;     // Default: YES
extern NSString * const kRCUpdateCheckIntervalKey;      // Default: 86400

// Beta
extern NSString * const kRCBetaPastePlainText;                      // Default: YES
extern NSString * const kRCBetaPastePlainTextModifier;              // Default: 0 (Cmd)
extern NSString * const kRCBetaDeleteHistory;                       // Default: NO
extern NSString * const kRCBetaDeleteHistoryModifier;               // Default: 0 (Cmd)
extern NSString * const kRCBetaPasteAndDeleteHistory;               // Default: NO
extern NSString * const kRCBetaPasteAndDeleteHistoryModifier;       // Default: 0 (Cmd)
extern NSString * const kRCBetaObserveScreenshot;                   // Default: NO

// Exclude
extern NSString * const kRCExcludeApplications;

// Snippets
extern NSString * const kRCSuppressAlertForDeleteSnippet;

// Paths
extern NSString * const kRCApplicationSupportDirectoryPath;         // ~/Library/Application Support/Revclip/
extern NSString * const kRCClipDataDirectoryPath;                   // ~/Library/Application Support/Revclip/ClipsData/

NS_ASSUME_NONNULL_END

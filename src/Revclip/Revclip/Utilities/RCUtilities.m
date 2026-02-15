//
//  RCUtilities.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCUtilities.h"

#import "RCConstants.h"

@implementation RCUtilities

+ (void)registerDefaultSettings {
    NSDictionary *defaultSettings = @{
        kRCPrefMaxHistorySizeKey: @30,
        kRCPrefInputPasteCommandKey: @YES,
        kRCPrefReorderClipsAfterPasting: @YES,
        kRCPrefShowStatusItemKey: @1,
        kRCPrefStoreTypesKey: @{
            @"String": @YES,
            @"RTF": @YES,
            @"RTFD": @YES,
            @"PDF": @YES,
            @"Filenames": @YES,
            @"URL": @YES,
            @"TIFF": @YES
        },
        kRCPrefOverwriteSameHistory: @YES,
        kRCPrefCopySameHistory: @YES,
        kRCCollectCrashReport: @YES,
        kRCLoginItem: @YES,
        kRCSuppressAlertForLoginItem: @NO,
        kRCPrefNumberOfItemsPlaceInlineKey: @0,
        kRCPrefNumberOfItemsPlaceInsideFolderKey: @10,
        kRCPrefMaxMenuItemTitleLengthKey: @40,
        kRCPrefMenuIconSizeKey: @16,
        kRCPrefShowIconInTheMenuKey: @YES,
        kRCMenuItemsAreMarkedWithNumbersKey: @YES,
        kRCPrefMenuItemsTitleStartWithZeroKey: @NO,
        kRCShowToolTipOnMenuItemKey: @YES,
        kRCMaxLengthOfToolTipKey: @10000,
        kRCShowImageInTheMenuKey: @YES,
        kRCPrefShowColorPreviewInTheMenu: @YES,
        kRCAddNumericKeyEquivalentsKey: @NO,
        kRCThumbnailWidthKey: @100,
        kRCThumbnailHeightKey: @32,
        kRCPrefAddClearHistoryMenuItemKey: @YES,
        kRCPrefShowAlertBeforeClearHistoryKey: @YES,
        kRCEnableAutomaticCheckKey: @YES,
        kRCUpdateCheckIntervalKey: @86400,
        kRCBetaPastePlainText: @YES,
        kRCBetaPastePlainTextModifier: @0,
        kRCBetaDeleteHistory: @NO,
        kRCBetaDeleteHistoryModifier: @0,
        kRCBetaPasteAndDeleteHistory: @NO,
        kRCBetaPasteAndDeleteHistoryModifier: @0,
        kRCBetaObserveScreenshot: @NO,
        kRCSuppressAlertForDeleteSnippet: @NO,
    };

    [[NSUserDefaults standardUserDefaults] registerDefaults:defaultSettings];
}

+ (NSString *)applicationSupportPath {
    NSString *configuredPath = [kRCApplicationSupportDirectoryPath stringByExpandingTildeInPath];
    if (configuredPath.length > 0) {
        return [configuredPath stringByStandardizingPath];
    }

    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *basePath = paths.firstObject;
    if (basePath.length == 0) {
        basePath = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library"] stringByAppendingPathComponent:@"Application Support"];
    }

    return [[basePath stringByAppendingPathComponent:@"Revclip"] stringByStandardizingPath];
}

+ (NSString *)clipDataDirectoryPath {
    NSString *configuredPath = [kRCClipDataDirectoryPath stringByExpandingTildeInPath];
    if (configuredPath.length > 0) {
        return [configuredPath stringByStandardizingPath];
    }

    NSString *clipPath = [[self applicationSupportPath] stringByAppendingPathComponent:@"ClipsData"];
    return [clipPath stringByStandardizingPath];
}

+ (BOOL)ensureDirectoryExists:(NSString *)path {
    NSString *expandedPath = [[path stringByExpandingTildeInPath] stringByStandardizingPath];
    if (expandedPath.length == 0) {
        return NO;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if ([fileManager fileExistsAtPath:expandedPath isDirectory:&isDirectory]) {
        return isDirectory;
    }

    NSError *error = nil;
    BOOL created = [fileManager createDirectoryAtPath:expandedPath
                          withIntermediateDirectories:YES
                                           attributes:nil
                                                error:&error];
    if (!created) {
        NSLog(@"[RCUtilities] Failed to create directory: %@ (%@)", expandedPath, error.localizedDescription);
    }
    return created;
}

@end

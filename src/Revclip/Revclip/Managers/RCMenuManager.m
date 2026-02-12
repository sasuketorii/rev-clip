//
//  RCMenuManager.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCMenuManager.h"

#import "RCClipboardService.h"
#import "RCClipData.h"
#import "RCClipItem.h"
#import "RCConstants.h"
#import "RCDatabaseManager.h"
#import "RCPasteService.h"
#import "NSColor+HexString.h"
#import "NSImage+Color.h"
#import "NSImage+Resize.h"
#import "RCUtilities.h"

static NSString * const kRCStatusBarIconAssetName = @"StatusBarIcon";
static NSString * const kRCNoHistoryTitle = @"No History";
static NSString * const kRCNoSnippetsTitle = @"No Snippets";
static NSString * const kRCEmptySnippetFolderTitle = @"(Empty)";
static NSInteger const kRCMaximumNumberedMenuItems = 10;

@interface RCMenuManager ()

@property (nonatomic, strong, nullable) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenu *statusMenu;

@end

@implementation RCMenuManager

+ (instancetype)shared {
    static RCMenuManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _statusMenu = [[NSMenu alloc] initWithTitle:@"Revclip"];

        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter addObserver:self
                               selector:@selector(handleClipboardDidChange:)
                                   name:RCClipboardDidChangeNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(handleUserDefaultsDidChange:)
                                   name:NSUserDefaultsDidChangeNotification
                                 object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Public

- (void)setupStatusItem {
    [self performOnMainThread:^{
        [self applyStatusItemPreference];
        [self rebuildMenuInternal];
    }];
}

- (void)rebuildMenu {
    [self performOnMainThread:^{
        [self applyStatusItemPreference];
        [self rebuildMenuInternal];
    }];
}

#pragma mark - Notification

- (void)handleClipboardDidChange:(NSNotification *)notification {
    (void)notification;
    [self rebuildMenu];
}

- (void)handleUserDefaultsDidChange:(NSNotification *)notification {
    (void)notification;
    [self setupStatusItem];
}

#pragma mark - Status Item

- (void)applyStatusItemPreference {
    NSInteger statusItemStyle = [self integerPreferenceForKey:kRCPrefShowStatusItemKey defaultValue:1];

    if (statusItemStyle == 0) {
        [self removeStatusItemIfNeeded];
        return;
    }

    if (self.statusItem == nil) {
        self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    }

    NSStatusBarButton *button = self.statusItem.button;
    if (button != nil) {
        button.image = [self statusBarIconImage];
        button.imagePosition = NSImageOnly;
    }

    self.statusItem.menu = self.statusMenu;
}

- (void)removeStatusItemIfNeeded {
    if (self.statusItem == nil) {
        return;
    }

    [[NSStatusBar systemStatusBar] removeStatusItem:self.statusItem];
    self.statusItem = nil;
}

- (NSImage *)statusBarIconImage {
    NSImage *image = [NSImage imageNamed:kRCStatusBarIconAssetName];
    if (image == nil) {
        image = [NSImage imageNamed:NSImageNameSmartBadgeTemplate];
    }
    if (image == nil) {
        image = [NSImage imageWithSystemSymbolName:@"doc.on.clipboard" accessibilityDescription:@"Revclip"];
    }

    if (image == nil) {
        image = [[NSImage alloc] initWithSize:NSMakeSize(18.0, 18.0)];
    }

    image.template = YES;
    return image;
}

#pragma mark - Menu Build

- (void)rebuildMenuInternal {
    if (self.statusItem == nil) {
        return;
    }

    [self.statusMenu removeAllItems];
    [self appendClipHistorySectionToMenu:self.statusMenu];
    [self.statusMenu addItem:[NSMenuItem separatorItem]];
    [self appendSnippetSectionToMenu:self.statusMenu];

    BOOL addClearHistory = [self boolPreferenceForKey:kRCPrefAddClearHistoryMenuItemKey defaultValue:YES];
    if (addClearHistory) {
        [self.statusMenu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *clearHistoryItem = [[NSMenuItem alloc] initWithTitle:@"Clear History"
                                                                   action:@selector(clearHistoryMenuItemSelected:)
                                                            keyEquivalent:@""];
        clearHistoryItem.target = self;
        [self.statusMenu addItem:clearHistoryItem];
    }

    [self.statusMenu addItem:[NSMenuItem separatorItem]];
    [self appendApplicationSectionToMenu:self.statusMenu];
    self.statusItem.menu = self.statusMenu;
}

- (void)appendClipHistorySectionToMenu:(NSMenu *)menu {
    RCDatabaseManager *databaseManager = [RCDatabaseManager shared];
    NSInteger clipCount = [databaseManager clipItemCount];
    NSArray<NSDictionary *> *clipRows = @[];
    if (clipCount > 0) {
        clipRows = [databaseManager fetchClipItemsWithLimit:clipCount];
    }

    if (clipRows.count == 0) {
        NSMenuItem *noHistoryItem = [[NSMenuItem alloc] initWithTitle:kRCNoHistoryTitle
                                                               action:nil
                                                        keyEquivalent:@""];
        noHistoryItem.enabled = NO;
        [menu addItem:noHistoryItem];
        return;
    }

    NSMutableArray<RCClipItem *> *clipItems = [NSMutableArray arrayWithCapacity:clipRows.count];
    for (NSDictionary *row in clipRows) {
        [clipItems addObject:[[RCClipItem alloc] initWithDictionary:row]];
    }

    NSUInteger inlineLimit = (NSUInteger)MAX(0, [self integerPreferenceForKey:kRCPrefNumberOfItemsPlaceInlineKey defaultValue:0]);
    NSUInteger folderChunkSize = (NSUInteger)MAX(1, [self integerPreferenceForKey:kRCPrefNumberOfItemsPlaceInsideFolderKey defaultValue:10]);

    NSUInteger inlineCount = MIN(inlineLimit, clipItems.count);
    for (NSUInteger index = 0; index < inlineCount; index++) {
        NSMenuItem *menuItem = [self clipMenuItemForClipItem:clipItems[index] globalIndex:index];
        [menu addItem:menuItem];
    }

    for (NSUInteger groupStart = inlineCount; groupStart < clipItems.count; groupStart += folderChunkSize) {
        NSUInteger groupEnd = MIN(groupStart + folderChunkSize, clipItems.count);
        NSString *folderTitle = [NSString stringWithFormat:@"Items %lu-%lu",
                                 (unsigned long)(groupStart + 1),
                                 (unsigned long)groupEnd];

        NSMenuItem *folderItem = [[NSMenuItem alloc] initWithTitle:folderTitle
                                                             action:nil
                                                      keyEquivalent:@""];
        NSMenu *folderMenu = [[NSMenu alloc] initWithTitle:folderTitle];
        folderItem.submenu = folderMenu;

        for (NSUInteger index = groupStart; index < groupEnd; index++) {
            NSMenuItem *menuItem = [self clipMenuItemForClipItem:clipItems[index] globalIndex:index];
            [folderMenu addItem:menuItem];
        }

        [menu addItem:folderItem];
    }
}

- (void)appendSnippetSectionToMenu:(NSMenu *)menu {
    NSArray<NSDictionary *> *folders = [[RCDatabaseManager shared] fetchAllSnippetFolders];
    BOOL hasAtLeastOneFolder = NO;

    for (NSDictionary *folder in folders) {
        BOOL enabled = [self boolValueFromDictionary:folder key:@"enabled" defaultValue:YES];
        if (!enabled) {
            continue;
        }

        NSString *identifier = [self stringValueFromDictionary:folder key:@"identifier" defaultValue:@""];
        if (identifier.length == 0) {
            continue;
        }

        NSString *title = [self stringValueFromDictionary:folder key:@"title" defaultValue:@""];
        if (title.length == 0) {
            title = @"Untitled Folder";
        }

        NSMenuItem *folderItem = [[NSMenuItem alloc] initWithTitle:title
                                                             action:nil
                                                      keyEquivalent:@""];
        NSMenu *folderMenu = [[NSMenu alloc] initWithTitle:title];
        folderItem.submenu = folderMenu;
        [menu addItem:folderItem];
        hasAtLeastOneFolder = YES;

        NSArray<NSDictionary *> *snippets = [[RCDatabaseManager shared] fetchSnippetsForFolder:identifier];
        BOOL hasSnippet = NO;
        for (NSDictionary *snippet in snippets) {
            BOOL snippetEnabled = [self boolValueFromDictionary:snippet key:@"enabled" defaultValue:YES];
            if (!snippetEnabled) {
                continue;
            }

            NSString *snippetTitle = [self stringValueFromDictionary:snippet key:@"title" defaultValue:@""];
            NSString *snippetContent = [self stringValueFromDictionary:snippet key:@"content" defaultValue:@""];

            if (snippetTitle.length == 0 && snippetContent.length > 0) {
                snippetTitle = [self truncatedString:snippetContent maxLength:24];
            }
            if (snippetTitle.length == 0) {
                snippetTitle = @"Untitled Snippet";
            }

            NSMenuItem *snippetItem = [[NSMenuItem alloc] initWithTitle:snippetTitle
                                                                  action:@selector(selectSnippetMenuItem:)
                                                           keyEquivalent:@""];
            snippetItem.target = self;
            snippetItem.representedObject = snippetContent ?: @"";
            [folderMenu addItem:snippetItem];
            hasSnippet = YES;
        }

        if (!hasSnippet) {
            NSMenuItem *emptyItem = [[NSMenuItem alloc] initWithTitle:kRCEmptySnippetFolderTitle
                                                               action:nil
                                                        keyEquivalent:@""];
            emptyItem.enabled = NO;
            [folderMenu addItem:emptyItem];
        }
    }

    if (!hasAtLeastOneFolder) {
        NSMenuItem *noSnippetsItem = [[NSMenuItem alloc] initWithTitle:kRCNoSnippetsTitle
                                                                 action:nil
                                                          keyEquivalent:@""];
        noSnippetsItem.enabled = NO;
        [menu addItem:noSnippetsItem];
    }
}

- (void)appendApplicationSectionToMenu:(NSMenu *)menu {
    NSMenuItem *preferencesItem = [[NSMenuItem alloc] initWithTitle:@"Preferences..."
                                                              action:@selector(openPreferences:)
                                                       keyEquivalent:@","];
    preferencesItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    preferencesItem.target = self;
    [menu addItem:preferencesItem];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit Revclip"
                                                       action:@selector(terminate:)
                                                keyEquivalent:@"q"];
    quitItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    quitItem.target = NSApp;
    [menu addItem:quitItem];
}

#pragma mark - Clip Menu Item

- (NSMenuItem *)clipMenuItemForClipItem:(RCClipItem *)clipItem globalIndex:(NSUInteger)globalIndex {
    NSString *menuTitle = [self menuTitleForClipItem:clipItem globalIndex:globalIndex];

    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:menuTitle
                                                  action:@selector(selectClipMenuItem:)
                                           keyEquivalent:@""];
    item.target = self;
    item.representedObject = clipItem.dataHash ?: @"";

    RCClipData *clipData = [RCClipData clipDataFromPath:clipItem.dataPath];
    if ([self boolPreferenceForKey:kRCShowToolTipOnMenuItemKey defaultValue:YES]) {
        NSString *toolTip = [self tooltipForClipItem:clipItem clipData:clipData];
        if (toolTip.length > 0) {
            NSInteger maxLength = [self integerPreferenceForKey:kRCMaxLengthOfToolTipKey defaultValue:200];
            item.toolTip = [self truncatedString:toolTip maxLength:MAX(1, maxLength)];
        }
    }

    NSImage *image = [self imageForClipItem:clipItem clipData:clipData];
    if (image != nil) {
        item.image = image;
    }

    if ([self boolPreferenceForKey:kRCAddNumericKeyEquivalentsKey defaultValue:NO]) {
        NSString *numericKey = [self numericKeyEquivalentForGlobalIndex:globalIndex];
        if (numericKey.length > 0) {
            item.keyEquivalent = numericKey;
            item.keyEquivalentModifierMask = 0;
        }
    }

    return item;
}

- (NSString *)menuTitleForClipItem:(RCClipItem *)clipItem globalIndex:(NSUInteger)globalIndex {
    NSString *title = clipItem.title ?: @"";
    if (title.length == 0) {
        title = [self fallbackTitleForPrimaryType:clipItem.primaryType];
    }

    NSInteger maxLength = [self integerPreferenceForKey:kRCPrefMaxMenuItemTitleLengthKey defaultValue:20];
    title = [self truncatedString:title maxLength:MAX(1, maxLength)];

    BOOL shouldPrefixIndex = [self boolPreferenceForKey:kRCMenuItemsAreMarkedWithNumbersKey defaultValue:YES];
    if (!shouldPrefixIndex) {
        return title;
    }

    BOOL startWithZero = [self boolPreferenceForKey:kRCPrefMenuItemsTitleStartWithZeroKey defaultValue:NO];
    NSInteger number = startWithZero ? (NSInteger)globalIndex : ((NSInteger)globalIndex + 1);
    return [NSString stringWithFormat:@"%ld. %@", (long)number, title];
}

- (NSString *)fallbackTitleForPrimaryType:(NSString *)primaryType {
    if ([primaryType isEqualToString:NSPasteboardTypeTIFF]) {
        return @"Image";
    }
    if ([primaryType isEqualToString:NSPasteboardTypeURL]) {
        return @"URL";
    }
    if ([primaryType isEqualToString:NSPasteboardTypePDF]) {
        return @"PDF";
    }
    if ([primaryType isEqualToString:NSPasteboardTypeRTF] || [primaryType isEqualToString:NSPasteboardTypeRTFD]) {
        return @"Rich Text";
    }
    if ([primaryType isEqualToString:NSPasteboardTypeFileURL]) {
        return @"Files";
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if ([primaryType isEqualToString:NSFilenamesPboardType]) {
        return @"Files";
    }
#pragma clang diagnostic pop
    return @"Clip";
}

- (NSString *)tooltipForClipItem:(RCClipItem *)clipItem clipData:(RCClipData *)clipData {
    if (clipData.stringValue.length > 0) {
        return clipData.stringValue;
    }
    if (clipData.URLString.length > 0) {
        return clipData.URLString;
    }
    if (clipItem.title.length > 0) {
        return clipItem.title;
    }
    return [self fallbackTitleForPrimaryType:clipItem.primaryType];
}

- (nullable NSImage *)imageForClipItem:(RCClipItem *)clipItem clipData:(RCClipData *)clipData {
    NSInteger preferredIconSize = [self integerPreferenceForKey:kRCPrefMenuIconSizeKey defaultValue:16];
    CGFloat iconSide = (CGFloat)MAX(8, preferredIconSize);
    NSSize iconSize = NSMakeSize(iconSide, iconSide);

    BOOL showColorPreview = [self boolPreferenceForKey:kRCPrefShowColorPreviewInTheMenu defaultValue:YES];
    if (showColorPreview && clipItem.isColorCode) {
        NSString *colorString = clipData.stringValue.length > 0 ? clipData.stringValue : clipItem.title;
        NSColor *color = [NSColor colorWithHexString:colorString];
        if (color != nil) {
            return [NSImage imageWithColor:color size:iconSize cornerRadius:3.0];
        }
    }

    BOOL showImagePreview = [self boolPreferenceForKey:kRCShowImageInTheMenuKey defaultValue:YES];
    if (showImagePreview) {
        NSImage *thumbnailImage = nil;
        if (clipItem.thumbnailPath.length > 0) {
            thumbnailImage = [[NSImage alloc] initWithContentsOfFile:clipItem.thumbnailPath];
        }
        if (thumbnailImage == nil && clipData.TIFFData.length > 0) {
            thumbnailImage = [[NSImage alloc] initWithData:clipData.TIFFData];
        }

        if (thumbnailImage != nil) {
            NSImage *resized = [thumbnailImage resizedImageToFitSize:iconSize];
            if (resized == nil) {
                resized = [thumbnailImage resizedImageToSize:iconSize];
            }
            if (resized != nil) {
                resized.template = NO;
                return resized;
            }
        }
    }

    BOOL showMenuIcon = [self boolPreferenceForKey:kRCPrefShowIconInTheMenuKey defaultValue:YES];
    if (!showMenuIcon) {
        return nil;
    }

    NSImage *typeImage = [self primaryTypeIconForType:clipItem.primaryType];
    NSImage *resizedImage = [typeImage resizedImageToFitSize:iconSize];
    if (resizedImage == nil) {
        resizedImage = [typeImage resizedImageToSize:iconSize];
    }
    if (resizedImage != nil) {
        resizedImage.template = YES;
        return resizedImage;
    }

    typeImage.size = iconSize;
    typeImage.template = YES;
    return typeImage;
}

- (NSImage *)primaryTypeIconForType:(NSString *)primaryType {
    NSString *symbolName = @"doc.on.doc";
    if ([primaryType isEqualToString:NSPasteboardTypeTIFF]) {
        symbolName = @"photo";
    } else if ([primaryType isEqualToString:NSPasteboardTypeURL]) {
        symbolName = @"link";
    } else if ([primaryType isEqualToString:NSPasteboardTypePDF]) {
        symbolName = @"doc.richtext";
    } else if ([primaryType isEqualToString:NSPasteboardTypeRTF]
               || [primaryType isEqualToString:NSPasteboardTypeRTFD]) {
        symbolName = @"doc.text";
    } else if ([primaryType isEqualToString:NSPasteboardTypeFileURL]) {
        symbolName = @"folder";
    }

    NSImage *image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
    if (image == nil) {
        image = [NSImage imageNamed:NSImageNameSmartBadgeTemplate];
    }
    if (image == nil) {
        image = [[NSImage alloc] initWithSize:NSMakeSize(16.0, 16.0)];
    }
    image.template = YES;
    return image;
}

- (NSString *)numericKeyEquivalentForGlobalIndex:(NSUInteger)globalIndex {
    if (globalIndex >= (NSUInteger)kRCMaximumNumberedMenuItems) {
        return @"";
    }

    BOOL startWithZero = [self boolPreferenceForKey:kRCPrefMenuItemsTitleStartWithZeroKey defaultValue:NO];
    NSInteger displayedNumber = startWithZero ? (NSInteger)globalIndex : ((NSInteger)globalIndex + 1);

    if (!startWithZero && displayedNumber == 10) {
        return @"0";
    }
    if (displayedNumber >= 0 && displayedNumber <= 9) {
        return [NSString stringWithFormat:@"%ld", (long)displayedNumber];
    }

    return @"";
}

#pragma mark - Actions

- (void)selectClipMenuItem:(NSMenuItem *)menuItem {
    NSString *dataHash = nil;
    if ([menuItem.representedObject isKindOfClass:[NSString class]]) {
        dataHash = (NSString *)menuItem.representedObject;
    }
    if (dataHash.length == 0) {
        return;
    }

    NSDictionary *clipRow = [[RCDatabaseManager shared] clipItemWithDataHash:dataHash];
    if (![clipRow isKindOfClass:[NSDictionary class]]) {
        return;
    }

    RCClipItem *clipItem = [[RCClipItem alloc] initWithDictionary:clipRow];
    if (clipItem.dataPath.length == 0) {
        return;
    }

    RCClipData *clipData = [RCClipData clipDataFromPath:clipItem.dataPath];
    if (clipData == nil) {
        return;
    }

    [[RCPasteService shared] pasteClipData:clipData];
}

- (void)selectSnippetMenuItem:(NSMenuItem *)menuItem {
    NSString *content = nil;
    if ([menuItem.representedObject isKindOfClass:[NSString class]]) {
        content = (NSString *)menuItem.representedObject;
    }
    if (content.length == 0) {
        return;
    }

    [[RCPasteService shared] pastePlainText:content];
}

- (void)clearHistoryMenuItemSelected:(NSMenuItem *)sender {
    (void)sender;

    BOOL shouldShowAlert = [self boolPreferenceForKey:kRCPrefShowAlertBeforeClearHistoryKey defaultValue:YES];
    if (shouldShowAlert) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleWarning;
        alert.messageText = @"Clear clipboard history?";
        alert.informativeText = @"All saved clips will be removed.";
        [alert addButtonWithTitle:@"Clear"];
        [alert addButtonWithTitle:@"Cancel"];

        NSModalResponse response = [alert runModal];
        if (response != NSAlertFirstButtonReturn) {
            return;
        }
    }

    RCClipboardService *clipboardService = [RCClipboardService shared];
    BOOL wasMonitoring = clipboardService.isMonitoring;
    if (wasMonitoring) {
        [clipboardService stopMonitoring];
    }

    @try {
        RCDatabaseManager *databaseManager = [RCDatabaseManager shared];
        NSInteger clipCount = [databaseManager clipItemCount];
        NSArray<NSDictionary *> *clipRows = @[];
        if (clipCount > 0) {
            clipRows = [databaseManager fetchClipItemsWithLimit:clipCount];
        }

        if (![databaseManager deleteAllClipItems]) {
            return;
        }

        for (NSDictionary *row in clipRows) {
            RCClipItem *item = [[RCClipItem alloc] initWithDictionary:row];
            [self removeFileAtPath:item.dataPath];
            [self removeFileAtPath:item.thumbnailPath];
        }

        [self removeAllClipDataFilesFromDisk];
        [self rebuildMenu];
    } @finally {
        if (wasMonitoring) {
            [clipboardService startMonitoring];
        }
    }
}

- (void)openPreferences:(NSMenuItem *)sender {
    (void)sender;

    NSArray<NSString *> *selectorNames = @[@"showPreferencesWindow:", @"showPreferences:"];
    for (NSString *selectorName in selectorNames) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([NSApp sendAction:selector to:nil from:self]) {
            return;
        }
    }

    NSBeep();
}

#pragma mark - Helpers

- (void)removeAllClipDataFilesFromDisk {
    NSString *clipDirectoryPath = [RCUtilities clipDataDirectoryPath];
    NSString *expandedPath = [[clipDirectoryPath stringByExpandingTildeInPath] stringByStandardizingPath];
    if (expandedPath.length == 0) {
        return;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray<NSString *> *children = [fileManager contentsOfDirectoryAtPath:expandedPath error:nil];
    for (NSString *child in children) {
        NSString *itemPath = [expandedPath stringByAppendingPathComponent:child];
        [self removeFileAtPath:itemPath];
    }
}

- (void)removeFileAtPath:(NSString *)path {
    if (path.length == 0) {
        return;
    }

    NSString *expandedPath = [[path stringByExpandingTildeInPath] stringByStandardizingPath];
    if (expandedPath.length == 0) {
        return;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:expandedPath]) {
        return;
    }

    NSError *error = nil;
    BOOL removed = [fileManager removeItemAtPath:expandedPath error:&error];
    if (!removed) {
        NSLog(@"[RCMenuManager] Failed to remove file at '%@': %@", expandedPath, error.localizedDescription);
    }
}

- (NSString *)truncatedString:(NSString *)string maxLength:(NSInteger)maxLength {
    if (string.length == 0 || maxLength <= 0 || string.length <= (NSUInteger)maxLength) {
        return string ?: @"";
    }

    if (maxLength <= 3) {
        NSRange safeRange = [string rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, (NSUInteger)maxLength)];
        return [string substringWithRange:safeRange];
    }

    NSUInteger bodyLength = (NSUInteger)(maxLength - 3);
    NSRange safeRange = [string rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, bodyLength)];
    NSString *truncated = [string substringWithRange:safeRange];
    return [truncated stringByAppendingString:@"..."];
}

- (BOOL)boolPreferenceForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
    id rawValue = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if ([rawValue isKindOfClass:[NSNumber class]]) {
        return [rawValue boolValue];
    }
    if ([rawValue isKindOfClass:[NSString class]]) {
        return [(NSString *)rawValue boolValue];
    }
    return defaultValue;
}

- (NSInteger)integerPreferenceForKey:(NSString *)key defaultValue:(NSInteger)defaultValue {
    id rawValue = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if ([rawValue isKindOfClass:[NSNumber class]]) {
        return [rawValue integerValue];
    }
    if ([rawValue isKindOfClass:[NSString class]]) {
        return [(NSString *)rawValue integerValue];
    }
    return defaultValue;
}

- (void)performOnMainThread:(dispatch_block_t)block {
    if ([NSThread isMainThread]) {
        block();
        return;
    }

    dispatch_async(dispatch_get_main_queue(), block);
}

- (NSString *)stringValueFromDictionary:(NSDictionary *)dictionary key:(NSString *)key defaultValue:(NSString *)defaultValue {
    id rawValue = dictionary[key];
    if ([rawValue isKindOfClass:[NSString class]]) {
        return (NSString *)rawValue;
    }
    if ([rawValue respondsToSelector:@selector(stringValue)]) {
        return [rawValue stringValue];
    }
    return defaultValue;
}

- (BOOL)boolValueFromDictionary:(NSDictionary *)dictionary key:(NSString *)key defaultValue:(BOOL)defaultValue {
    id rawValue = dictionary[key];
    if ([rawValue isKindOfClass:[NSNumber class]]) {
        return [rawValue boolValue];
    }
    if ([rawValue isKindOfClass:[NSString class]]) {
        return [(NSString *)rawValue boolValue];
    }
    return defaultValue;
}

@end

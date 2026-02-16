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
#import "RCHotKeyService.h"
#import "RCPanicEraseService.h"
#import "RCPasteService.h"
#import "FMDB.h"
#import "NSColor+HexString.h"
#import "NSImage+Color.h"
#import "NSImage+Resize.h"
#import "RCUtilities.h"
#import <os/log.h>

static NSString * const kRCStatusBarIconAssetName = @"StatusBarIcon";
static NSInteger const kRCMaximumNumberedMenuItems = 9;
static NSString * const kRCMemoryWarningNotificationName = @"NSApplicationDidReceiveMemoryWarningNotification";
static NSString * const kRCClipDataFileExtension = @"rcclip";
static NSString * const kRCThumbnailFileExtension = @"thumb";
static NSString * const kRCLegacyThumbnailFileSuffix = @".thumbnail.tiff";
static NSString * const kRCSnippetMenuFolderIdentifierKey = @"folderIdentifier";
static NSString * const kRCSnippetMenuSnippetIdentifierKey = @"snippetIdentifier";

static os_log_t RCMenuManagerLog(void) {
    static os_log_t logger = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        logger = os_log_create("com.revclip", "RCMenuManager");
    });
    return logger;
}

@interface RCMenuManager () <NSMenuDelegate>

@property (nonatomic, strong, nullable) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenu *statusMenu;
@property (nonatomic, strong, nullable) dispatch_block_t defaultsChangeDebounceBlock;
@property (nonatomic, strong) NSCache<NSString *, NSImage *> *thumbnailCache;
@property (nonatomic, strong) dispatch_queue_t thumbnailGenerationQueue;

- (void)prefetchThumbnailsForClipItems:(NSArray<RCClipItem *> *)clipItems;
- (NSString *)thumbnailCacheKeyForClipItem:(RCClipItem *)clipItem;
- (void)loadThumbnailForClipItem:(RCClipItem *)clipItem
                        cacheKey:(NSString *)cacheKey
                updatingMenuItem:(NSMenuItem *)menuItem
                    numberPrefix:(NSString *)numberPrefix
                       baseTitle:(NSString *)baseTitle;
- (nullable NSImage *)resizedThumbnailImageAtPath:(NSString *)thumbnailPath targetSize:(NSSize)targetSize;
- (NSArray<NSString *> *)clipDataFilePathsSnapshotForCurrentHistoryWithDatabaseManager:(RCDatabaseManager *)databaseManager;
- (void)removeClipDataFilesAtPaths:(NSArray<NSString *> *)paths;
- (nullable NSString *)snippetContentForFolderIdentifier:(NSString *)folderIdentifier snippetIdentifier:(NSString *)snippetIdentifier;
- (void)handleMissingClipDataForClipItem:(RCClipItem *)clipItem reason:(NSString *)reason;
- (BOOL)isKnownClipDataFileName:(NSString *)fileName;
- (NSRange)composedSafePrefixRangeForString:(NSString *)string maxLength:(NSUInteger)maxLength;
- (NSString *)menuBaseTitleForClipItem:(RCClipItem *)clipItem;
- (NSString *)menuNumberPrefixForGlobalIndex:(NSUInteger)globalIndex;
- (void)applyMenuItemTitleForItem:(NSMenuItem *)item
                     numberPrefix:(NSString *)numberPrefix
                        baseTitle:(NSString *)baseTitle
                            image:(nullable NSImage *)image;
- (NSRect)attachmentBoundsForMenuImage:(NSImage *)image;

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
        _statusMenu = [self menuWithTitle:@"Revclip"];
        _thumbnailCache = [[NSCache alloc] init];
        _thumbnailGenerationQueue = dispatch_queue_create("com.revclip.menu.thumbnail", DISPATCH_QUEUE_CONCURRENT);

        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter addObserver:self
                               selector:@selector(handleClipboardDidChange:)
                                   name:RCClipboardDidChangeNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(handleUserDefaultsDidChange:)
                                   name:NSUserDefaultsDidChangeNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(handleHotKeyMainTriggered:)
                                   name:RCHotKeyMainTriggeredNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(handleHotKeyHistoryTriggered:)
                                   name:RCHotKeyHistoryTriggeredNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(handleHotKeySnippetTriggered:)
                                   name:RCHotKeySnippetTriggeredNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(handleHotKeyClearHistoryTriggered:)
                                   name:RCHotKeyClearHistoryTriggeredNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(handleHotKeySnippetFolderTriggered:)
                                   name:RCHotKeySnippetFolderTriggeredNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(handleApplicationDidReceiveMemoryWarning:)
                                   name:kRCMemoryWarningNotificationName
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

    [self.thumbnailCache removeAllObjects];

    if (self.defaultsChangeDebounceBlock != nil) {
        dispatch_block_cancel(self.defaultsChangeDebounceBlock);
    }

    dispatch_block_t debounceBlock = dispatch_block_create(0, ^{
        [self setupStatusItem];
    });
    self.defaultsChangeDebounceBlock = debounceBlock;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   debounceBlock);
}

- (void)handleHotKeyMainTriggered:(NSNotification *)notification {
    (void)notification;
    [self popUpStatusMenuFromHotKey];
}

- (void)handleHotKeyHistoryTriggered:(NSNotification *)notification {
    (void)notification;
    [self popUpHistoryMenuFromHotKey];
}

- (void)handleHotKeySnippetTriggered:(NSNotification *)notification {
    (void)notification;
    [self popUpSnippetMenuFromHotKey];
}

- (void)handleHotKeyClearHistoryTriggered:(NSNotification *)notification {
    (void)notification;
    [self performOnMainThread:^{
        [self clearHistoryMenuItemSelected:nil];
    }];
}

- (void)handleHotKeySnippetFolderTriggered:(NSNotification *)notification {
    id rawIdentifier = notification.userInfo[RCHotKeyFolderIdentifierUserInfoKey];
    NSString *identifier = [rawIdentifier isKindOfClass:[NSString class]] ? (NSString *)rawIdentifier : @"";
    if (identifier.length == 0) {
        return;
    }

    [self popUpSnippetFolderMenuFromHotKeyWithIdentifier:identifier];
}

- (void)handleApplicationDidReceiveMemoryWarning:(NSNotification *)notification {
    (void)notification;
    [self.thumbnailCache removeAllObjects];
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

    [self configureMenuForSimpleTransparentBackground:self.statusMenu];
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

- (void)popUpStatusMenuFromHotKey {
    [self performOnMainThread:^{
        [self applyStatusItemPreference];

        if (self.statusItem != nil) {
            [self rebuildMenuInternal];
            NSPoint mouseLocation = [NSEvent mouseLocation];
            [self.statusMenu popUpMenuPositioningItem:nil atLocation:mouseLocation inView:nil];
        } else {
            NSMenu *fallbackMenu = [self buildStandaloneMenu];
            NSPoint mouseLocation = [NSEvent mouseLocation];
            [fallbackMenu popUpMenuPositioningItem:nil atLocation:mouseLocation inView:nil];
        }
    }];
}

- (void)popUpHistoryMenuFromHotKey {
    [self performOnMainThread:^{
        [self applyStatusItemPreference];
        NSMenu *menu = [self menuWithTitle:@"History"];
        [self appendClipHistorySectionToMenu:menu];
        [menu addItem:[NSMenuItem separatorItem]];
        [self appendApplicationSectionToMenu:menu];
        [self popUpTransientMenu:menu];
    }];
}

- (void)popUpSnippetMenuFromHotKey {
    [self performOnMainThread:^{
        [self applyStatusItemPreference];
        NSMenu *menu = [self menuWithTitle:@"Snippets"];
        [self appendSnippetSectionToMenu:menu];
        [menu addItem:[NSMenuItem separatorItem]];
        [self appendApplicationSectionToMenu:menu];
        [self popUpTransientMenu:menu];
    }];
}

- (void)popUpSnippetFolderMenuFromHotKeyWithIdentifier:(NSString *)folderIdentifier {
    if (folderIdentifier.length == 0) {
        return;
    }

    [self performOnMainThread:^{
        [self applyStatusItemPreference];
        NSDictionary *targetFolder = nil;
        for (NSDictionary *folder in [[RCDatabaseManager shared] fetchAllSnippetFolders]) {
            NSString *identifier = [self stringValueFromDictionary:folder key:@"identifier" defaultValue:@""];
            if (![identifier isEqualToString:folderIdentifier]) {
                continue;
            }

            BOOL enabled = [self boolValueFromDictionary:folder key:@"enabled" defaultValue:YES];
            if (!enabled) {
                return;
            }

            targetFolder = folder;
            break;
        }

        if (targetFolder == nil) {
            return;
        }

        NSString *title = [self stringValueFromDictionary:targetFolder key:@"title" defaultValue:@""];
        if (title.length == 0) {
            title = NSLocalizedString(@"Untitled Folder", nil);
        }

        NSMenu *menu = [self menuWithTitle:title];
        [self appendSnippetsForFolderIdentifier:folderIdentifier toMenu:menu];
        [menu addItem:[NSMenuItem separatorItem]];
        [self appendApplicationSectionToMenu:menu];
        [self popUpTransientMenu:menu];
    }];
}

- (void)popUpTransientMenu:(NSMenu *)menu {
    if (menu == nil) {
        return;
    }

    [self configureMenuForSimpleTransparentBackground:menu];
    NSPoint mouseLocation = [NSEvent mouseLocation];
    [menu popUpMenuPositioningItem:nil atLocation:mouseLocation inView:nil];
}

#pragma mark - Menu Build

- (void)rebuildMenuInternal {
    if (self.statusItem == nil) {
        return;
    }

    [self configureMenuForSimpleTransparentBackground:self.statusMenu];
    [self.statusMenu removeAllItems];
    [self appendClipHistorySectionToMenu:self.statusMenu];
    [self.statusMenu addItem:[NSMenuItem separatorItem]];
    [self appendSnippetSectionToMenu:self.statusMenu];

    BOOL addClearHistory = [self boolPreferenceForKey:kRCPrefAddClearHistoryMenuItemKey defaultValue:YES];
    [self.statusMenu addItem:[NSMenuItem separatorItem]];
    if (addClearHistory) {
        NSMenuItem *clearHistoryItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Clear History", nil)
                                                                   action:@selector(clearHistoryMenuItemSelected:)
                                                            keyEquivalent:@""];
        clearHistoryItem.target = self;
        [self.statusMenu addItem:clearHistoryItem];
    }

    [self.statusMenu addItem:[NSMenuItem separatorItem]];
    [self appendApplicationSectionToMenu:self.statusMenu];
    self.statusItem.menu = self.statusMenu;
}

- (NSMenu *)buildStandaloneMenu {
    NSMenu *menu = [self menuWithTitle:@"Revclip"];
    [self appendClipHistorySectionToMenu:menu];
    [menu addItem:[NSMenuItem separatorItem]];
    [self appendSnippetSectionToMenu:menu];

    BOOL addClearHistory = [self boolPreferenceForKey:kRCPrefAddClearHistoryMenuItemKey defaultValue:YES];
    [menu addItem:[NSMenuItem separatorItem]];
    if (addClearHistory) {
        NSMenuItem *clearHistoryItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Clear History", nil)
                                                                   action:@selector(clearHistoryMenuItemSelected:)
                                                            keyEquivalent:@""];
        clearHistoryItem.target = self;
        [menu addItem:clearHistoryItem];
    }

    [menu addItem:[NSMenuItem separatorItem]];
    [self appendApplicationSectionToMenu:menu];
    return menu;
}

- (void)appendClipHistorySectionToMenu:(NSMenu *)menu {
    RCDatabaseManager *databaseManager = [RCDatabaseManager shared];
    NSInteger maxHistorySize = [self integerPreferenceForKey:kRCPrefMaxHistorySizeKey defaultValue:30];
    NSInteger limit = MAX(1, maxHistorySize);
    NSArray<NSDictionary *> *clipRows = @[];
    if ([databaseManager clipItemCount] > 0) {
        clipRows = [databaseManager fetchClipItemsWithLimit:limit];
    }

    if (clipRows.count == 0) {
        NSMenuItem *noHistoryItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"No History", nil)
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
    [self prefetchThumbnailsForClipItems:clipItems];

    NSUInteger inlineLimit = (NSUInteger)MAX(0, [self integerPreferenceForKey:kRCPrefNumberOfItemsPlaceInlineKey defaultValue:0]);
    NSUInteger folderChunkSize = (NSUInteger)MAX(1, [self integerPreferenceForKey:kRCPrefNumberOfItemsPlaceInsideFolderKey defaultValue:10]);

    NSUInteger inlineCount = MIN(inlineLimit, clipItems.count);
    for (NSUInteger index = 0; index < inlineCount; index++) {
        NSMenuItem *menuItem = [self clipMenuItemForClipItem:clipItems[index] globalIndex:index];
        [menu addItem:menuItem];
    }

    for (NSUInteger groupStart = inlineCount; groupStart < clipItems.count; groupStart += folderChunkSize) {
        NSUInteger groupEnd = MIN(groupStart + folderChunkSize, clipItems.count);
        NSString *folderTitle = [NSString stringWithFormat:NSLocalizedString(@"Items %lu-%lu", nil),
                                 (unsigned long)(groupStart + 1),
                                 (unsigned long)groupEnd];

        NSMenuItem *folderItem = [[NSMenuItem alloc] initWithTitle:folderTitle
                                                             action:nil
                                                      keyEquivalent:@""];
        NSMenu *folderMenu = [self menuWithTitle:folderTitle];
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
            title = NSLocalizedString(@"Untitled Folder", nil);
        }

        NSMenuItem *folderItem = [[NSMenuItem alloc] initWithTitle:title
                                                             action:nil
                                                      keyEquivalent:@""];
        NSMenu *folderMenu = [self menuWithTitle:title];
        folderItem.submenu = folderMenu;
        [menu addItem:folderItem];
        hasAtLeastOneFolder = YES;
        [self appendSnippetsForFolderIdentifier:identifier toMenu:folderMenu];
    }

    if (!hasAtLeastOneFolder) {
        NSMenuItem *noSnippetsItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"No Snippets", nil)
                                                                 action:nil
                                                          keyEquivalent:@""];
        noSnippetsItem.enabled = NO;
        [menu addItem:noSnippetsItem];
    }
}

- (void)appendSnippetsForFolderIdentifier:(NSString *)folderIdentifier toMenu:(NSMenu *)menu {
    if (folderIdentifier.length == 0 || menu == nil) {
        return;
    }

    NSArray<NSDictionary *> *snippets = [[RCDatabaseManager shared] fetchSnippetsForFolder:folderIdentifier];
    BOOL hasSnippet = NO;
    for (NSDictionary *snippet in snippets) {
        BOOL snippetEnabled = [self boolValueFromDictionary:snippet key:@"enabled" defaultValue:YES];
        if (!snippetEnabled) {
            continue;
        }

        NSString *snippetIdentifier = [self stringValueFromDictionary:snippet key:@"identifier" defaultValue:@""];
        if (snippetIdentifier.length == 0) {
            continue;
        }

        NSString *snippetTitle = [self stringValueFromDictionary:snippet key:@"title" defaultValue:@""];
        NSString *snippetContent = [self stringValueFromDictionary:snippet key:@"content" defaultValue:@""];

        if (snippetTitle.length == 0 && snippetContent.length > 0) {
            snippetTitle = [self truncatedString:snippetContent maxLength:24];
        }
        if (snippetTitle.length == 0) {
            snippetTitle = NSLocalizedString(@"Untitled Snippet", nil);
        }

        NSMenuItem *snippetItem = [[NSMenuItem alloc] initWithTitle:snippetTitle
                                                              action:@selector(selectSnippetMenuItem:)
                                                       keyEquivalent:@""];
        snippetItem.target = self;
        if (snippetContent.length > 0) {
            snippetItem.toolTip = [self truncatedString:snippetContent maxLength:200];
        }
        snippetItem.representedObject = @{
            kRCSnippetMenuFolderIdentifierKey: folderIdentifier,
            kRCSnippetMenuSnippetIdentifierKey: snippetIdentifier,
        };
        [menu addItem:snippetItem];
        hasSnippet = YES;
    }

    if (!hasSnippet) {
        NSMenuItem *emptyItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"(Empty)", nil)
                                                           action:nil
                                                    keyEquivalent:@""];
        emptyItem.enabled = NO;
        [menu addItem:emptyItem];
    }
}

- (void)appendApplicationSectionToMenu:(NSMenu *)menu {
    NSMenuItem *preferencesItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Preferences...", nil)
                                                              action:@selector(openPreferences:)
                                                       keyEquivalent:@","];
    preferencesItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    preferencesItem.target = self;
    [menu addItem:preferencesItem];

    NSMenuItem *editSnippetsItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Edit Templates...", nil)
                                                               action:@selector(openSnippetEditor:)
                                                        keyEquivalent:@""];
    editSnippetsItem.target = self;
    [menu addItem:editSnippetsItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Quit Revclip", nil)
                                                       action:@selector(terminate:)
                                                keyEquivalent:@"q"];
    quitItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    quitItem.target = NSApp;
    [menu addItem:quitItem];
}

- (NSMenu *)menuWithTitle:(NSString *)title {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:title ?: @""];
    menu.delegate = self;
    [self configureMenuForSimpleTransparentBackground:menu];
    return menu;
}

- (void)menuWillOpen:(NSMenu *)menu {
    [self configureMenuForSimpleTransparentBackground:menu];
}

- (void)configureMenuForSimpleTransparentBackground:(NSMenu *)menu {
    if (menu == nil) {
        return;
    }

    NSAppearance *appearance = [self nonVibrantMenuAppearance];
    if (appearance != nil) {
        menu.appearance = appearance;
    }
}

- (nullable NSAppearance *)nonVibrantMenuAppearance {
    // NSMenu has no public API to switch off blur directly; using a non-vibrant appearance
    // is the safest supported way to avoid vibrant menu rendering.
    NSAppearance *applicationAppearance = NSApp.effectiveAppearance;
    if (applicationAppearance != nil && !applicationAppearance.allowsVibrancy) {
        return applicationAppearance;
    }

    NSAppearance *referenceAppearance = applicationAppearance ?: [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    NSAppearanceName bestMatch = [referenceAppearance bestMatchFromAppearancesWithNames:@[
        NSAppearanceNameAccessibilityHighContrastDarkAqua,
        NSAppearanceNameAccessibilityHighContrastAqua,
        NSAppearanceNameDarkAqua,
        NSAppearanceNameAqua
    ]];

    NSAppearanceName targetName = NSAppearanceNameAqua;
    if ([bestMatch isEqualToString:NSAppearanceNameAccessibilityHighContrastDarkAqua]) {
        targetName = NSAppearanceNameAccessibilityHighContrastDarkAqua;
    } else if ([bestMatch isEqualToString:NSAppearanceNameAccessibilityHighContrastAqua]) {
        targetName = NSAppearanceNameAccessibilityHighContrastAqua;
    } else if ([bestMatch isEqualToString:NSAppearanceNameDarkAqua]) {
        targetName = NSAppearanceNameDarkAqua;
    }

    return [NSAppearance appearanceNamed:targetName];
}

#pragma mark - Clip Menu Item

- (NSMenuItem *)clipMenuItemForClipItem:(RCClipItem *)clipItem globalIndex:(NSUInteger)globalIndex {
    NSString *baseTitle = [self menuBaseTitleForClipItem:clipItem];
    NSString *numberPrefix = [self menuNumberPrefixForGlobalIndex:globalIndex];
    NSString *menuTitle = [self menuTitleForClipItem:clipItem globalIndex:globalIndex];

    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:menuTitle
                                                  action:@selector(selectClipMenuItem:)
                                           keyEquivalent:@""];
    item.target = self;
    item.representedObject = clipItem.dataHash ?: @"";
    [self applyMenuItemTitleForItem:item numberPrefix:numberPrefix baseTitle:baseTitle image:nil];

    BOOL needsTooltip = [self boolPreferenceForKey:kRCShowToolTipOnMenuItemKey defaultValue:YES];
    BOOL showImagePreview = [self boolPreferenceForKey:kRCShowImageInTheMenuKey defaultValue:YES];
    BOOL showColorPreview = [self boolPreferenceForKey:kRCPrefShowColorPreviewInTheMenu defaultValue:YES];
    BOOL showMenuIcon = [self boolPreferenceForKey:kRCPrefShowIconInTheMenuKey defaultValue:YES];

    BOOL tooltipSatisfied = NO;
    if (needsTooltip && clipItem.title.length > 0) {
        NSInteger maxLength = [self integerPreferenceForKey:kRCMaxLengthOfToolTipKey defaultValue:10000];
        item.toolTip = [self truncatedString:clipItem.title maxLength:MAX(1, maxLength)];
        tooltipSatisfied = YES;
    }

    BOOL imageSatisfied = NO;
    if (!clipItem.isColorCode) {
        NSString *thumbnailCacheKey = [self thumbnailCacheKeyForClipItem:clipItem];
        if (showImagePreview && clipItem.thumbnailPath.length > 0 && thumbnailCacheKey.length > 0) {
            NSImage *cachedThumbnail = [self.thumbnailCache objectForKey:thumbnailCacheKey];
            if (cachedThumbnail != nil) {
                [self applyMenuItemTitleForItem:item numberPrefix:numberPrefix baseTitle:baseTitle image:cachedThumbnail];
                imageSatisfied = YES;
            } else {
                if (showMenuIcon) {
                    NSImage *placeholderImage = [self typeIconForClipItem:clipItem];
                    if (placeholderImage != nil) {
                        [self applyMenuItemTitleForItem:item numberPrefix:numberPrefix baseTitle:baseTitle image:placeholderImage];
                        imageSatisfied = YES;
                    }
                }

                [self loadThumbnailForClipItem:clipItem
                                      cacheKey:thumbnailCacheKey
                              updatingMenuItem:item
                                  numberPrefix:numberPrefix
                                     baseTitle:baseTitle];
            }
        }

        if (!imageSatisfied && showMenuIcon) {
            NSImage *iconImage = [self typeIconForClipItem:clipItem];
            if (iconImage != nil) {
                [self applyMenuItemTitleForItem:item numberPrefix:numberPrefix baseTitle:baseTitle image:iconImage];
                imageSatisfied = YES;
            }
        }
    } else if (!showColorPreview && showMenuIcon) {
        NSImage *iconImage = [self typeIconForClipItem:clipItem];
        if (iconImage != nil) {
            [self applyMenuItemTitleForItem:item numberPrefix:numberPrefix baseTitle:baseTitle image:iconImage];
            imageSatisfied = YES;
        }
    }

    BOOL needsClipDataForTooltip = needsTooltip && !tooltipSatisfied;
    BOOL needsClipDataForImage = showColorPreview && clipItem.isColorCode && !imageSatisfied;
    if (needsClipDataForTooltip || needsClipDataForImage) {
        RCClipData *clipData = [RCClipData clipDataFromPath:clipItem.dataPath];

        if (needsClipDataForTooltip) {
            NSString *toolTip = [self tooltipForClipItem:clipItem clipData:clipData];
            if (toolTip.length > 0) {
                NSInteger maxLength = [self integerPreferenceForKey:kRCMaxLengthOfToolTipKey defaultValue:10000];
                item.toolTip = [self truncatedString:toolTip maxLength:MAX(1, maxLength)];
            }
        }

        if (needsClipDataForImage) {
            NSImage *image = [self imageForClipItem:clipItem clipData:clipData];
            if (image != nil) {
                [self applyMenuItemTitleForItem:item numberPrefix:numberPrefix baseTitle:baseTitle image:image];
            }
        }
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
    NSString *baseTitle = [self menuBaseTitleForClipItem:clipItem];
    NSString *numberPrefix = [self menuNumberPrefixForGlobalIndex:globalIndex];
    if (numberPrefix.length == 0) {
        return baseTitle;
    }
    return [numberPrefix stringByAppendingString:baseTitle];
}

- (NSString *)menuBaseTitleForClipItem:(RCClipItem *)clipItem {
    NSString *title = clipItem.title ?: @"";
    if (title.length == 0) {
        title = [self fallbackTitleForPrimaryType:clipItem.primaryType];
    }

    NSInteger maxLength = [self integerPreferenceForKey:kRCPrefMaxMenuItemTitleLengthKey defaultValue:40];
    return [self truncatedString:title maxLength:MAX(1, maxLength)];
}

- (NSString *)menuNumberPrefixForGlobalIndex:(NSUInteger)globalIndex {
    BOOL shouldPrefixIndex = [self boolPreferenceForKey:kRCMenuItemsAreMarkedWithNumbersKey defaultValue:YES];
    if (!shouldPrefixIndex) {
        return @"";
    }

    BOOL startWithZero = [self boolPreferenceForKey:kRCPrefMenuItemsTitleStartWithZeroKey defaultValue:NO];
    NSInteger number = startWithZero ? (NSInteger)globalIndex : ((NSInteger)globalIndex + 1);
    return [NSString stringWithFormat:@"%ld. ", (long)number];
}

- (void)applyMenuItemTitleForItem:(NSMenuItem *)item
                     numberPrefix:(NSString *)numberPrefix
                        baseTitle:(NSString *)baseTitle
                            image:(nullable NSImage *)image {
    if (item == nil) {
        return;
    }

    NSString *safeNumberPrefix = numberPrefix ?: @"";
    NSString *safeBaseTitle = baseTitle ?: @"";
    NSString *plainTitle = (safeNumberPrefix.length > 0) ? [safeNumberPrefix stringByAppendingString:safeBaseTitle] : safeBaseTitle;

    item.title = plainTitle;

    if (image != nil && safeNumberPrefix.length > 0) {
        NSDictionary<NSAttributedStringKey, id> *attributes = @{
            NSFontAttributeName: [NSFont menuFontOfSize:0]
        };

        NSMutableAttributedString *attributedTitle = [[NSMutableAttributedString alloc] initWithString:safeNumberPrefix
                                                                                             attributes:attributes];
        NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
        attachment.image = image;
        attachment.bounds = [self attachmentBoundsForMenuImage:image];
        [attributedTitle appendAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];

        if (safeBaseTitle.length > 0) {
            NSString *suffix = [NSString stringWithFormat:@" %@", safeBaseTitle];
            [attributedTitle appendAttributedString:[[NSAttributedString alloc] initWithString:suffix attributes:attributes]];
        }

        item.attributedTitle = attributedTitle;
        item.image = nil;
        return;
    }

    item.attributedTitle = nil;
    item.image = image;
}

- (NSRect)attachmentBoundsForMenuImage:(NSImage *)image {
    if (image == nil) {
        return NSMakeRect(0.0, -2.0, 16.0, 16.0);
    }

    NSSize imageSize = image.size;
    if (imageSize.width <= 0.0 || imageSize.height <= 0.0) {
        return NSMakeRect(0.0, -2.0, 16.0, 16.0);
    }

    if (imageSize.width <= 20.0 && imageSize.height <= 20.0) {
        return NSMakeRect(0.0, -2.0, 16.0, 16.0);
    }

    CGFloat maxDimension = 40.0;
    CGFloat scale = MIN(maxDimension / imageSize.width, maxDimension / imageSize.height);
    if (scale > 1.0) {
        scale = 1.0;
    }
    CGFloat width = floor(imageSize.width * scale);
    CGFloat height = floor(imageSize.height * scale);
    return NSMakeRect(0.0, -10.0, width, height);
}

- (NSString *)fallbackTitleForPrimaryType:(NSString *)primaryType {
    if ([primaryType isEqualToString:NSPasteboardTypeTIFF]) {
        return NSLocalizedString(@"Image", nil);
    }
    if ([primaryType isEqualToString:NSPasteboardTypeURL]) {
        return NSLocalizedString(@"URL", nil);
    }
    if ([primaryType isEqualToString:NSPasteboardTypePDF]) {
        return NSLocalizedString(@"PDF", nil);
    }
    if ([primaryType isEqualToString:NSPasteboardTypeRTF] || [primaryType isEqualToString:NSPasteboardTypeRTFD]) {
        return NSLocalizedString(@"Rich Text", nil);
    }
    if ([primaryType isEqualToString:NSPasteboardTypeFileURL]) {
        return NSLocalizedString(@"Files", nil);
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if ([primaryType isEqualToString:NSFilenamesPboardType]) {
        return NSLocalizedString(@"Files", nil);
    }
#pragma clang diagnostic pop
    return NSLocalizedString(@"Clip", nil);
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
    BOOL showColorPreview = [self boolPreferenceForKey:kRCPrefShowColorPreviewInTheMenu defaultValue:YES];
    if (showColorPreview && clipItem.isColorCode) {
        NSString *colorString = clipData.stringValue.length > 0 ? clipData.stringValue : clipItem.title;
        NSColor *color = [NSColor colorWithHexString:colorString];
        if (color != nil) {
            NSSize colorPreviewSize = NSMakeSize(16.0, 16.0);
            return [NSImage imageWithColor:color size:colorPreviewSize cornerRadius:3.0];
        }
    }

    BOOL showImagePreview = [self boolPreferenceForKey:kRCShowImageInTheMenuKey defaultValue:YES];
    if (showImagePreview) {
        CGFloat thumbnailWidth = (CGFloat)MIN(512, MAX(16, [self integerPreferenceForKey:kRCThumbnailWidthKey defaultValue:100]));
        CGFloat thumbnailHeight = (CGFloat)MIN(512, MAX(16, [self integerPreferenceForKey:kRCThumbnailHeightKey defaultValue:32]));
        NSSize thumbnailSize = NSMakeSize(thumbnailWidth, thumbnailHeight);

        NSImage *thumbnailImage = nil;
        if (clipData.TIFFData.length > 0) {
            thumbnailImage = [[NSImage alloc] initWithData:clipData.TIFFData];
        }
        if (thumbnailImage == nil && clipItem.thumbnailPath.length > 0) {
            thumbnailImage = [[NSImage alloc] initWithContentsOfFile:clipItem.thumbnailPath];
        }

        if (thumbnailImage != nil) {
            NSImage *resized = [thumbnailImage resizedImageToFitSize:thumbnailSize];
            if (resized == nil) {
                resized = [thumbnailImage resizedImageToSize:thumbnailSize];
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

    return [self typeIconForClipItem:clipItem];
}

- (NSSize)thumbnailPreviewSize {
    CGFloat thumbnailWidth = (CGFloat)MIN(512, MAX(16, [self integerPreferenceForKey:kRCThumbnailWidthKey defaultValue:100]));
    CGFloat thumbnailHeight = (CGFloat)MIN(512, MAX(16, [self integerPreferenceForKey:kRCThumbnailHeightKey defaultValue:32]));
    return NSMakeSize(thumbnailWidth, thumbnailHeight);
}

- (NSString *)thumbnailCacheKeyForClipItem:(RCClipItem *)clipItem {
    NSString *dataPath = clipItem.dataPath ?: @"";
    if (clipItem.itemId <= 0 && dataPath.length == 0) {
        return @"";
    }
    return [NSString stringWithFormat:@"%ld|%@", (long)clipItem.itemId, dataPath];
}

- (void)prefetchThumbnailsForClipItems:(NSArray<RCClipItem *> *)clipItems {
    if (clipItems.count == 0) {
        return;
    }

    BOOL showImagePreview = [self boolPreferenceForKey:kRCShowImageInTheMenuKey defaultValue:YES];
    if (!showImagePreview) {
        return;
    }

    NSArray<RCClipItem *> *itemsToPrefetch = [clipItems copy];
    NSSize thumbnailSize = [self thumbnailPreviewSize];
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.thumbnailGenerationQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        for (RCClipItem *clipItem in itemsToPrefetch) {
            if (clipItem.isColorCode || clipItem.thumbnailPath.length == 0) {
                continue;
            }

            NSString *cacheKey = [strongSelf thumbnailCacheKeyForClipItem:clipItem];
            if (cacheKey.length == 0 || [strongSelf.thumbnailCache objectForKey:cacheKey] != nil) {
                continue;
            }

            NSImage *resizedImage = [strongSelf resizedThumbnailImageAtPath:clipItem.thumbnailPath
                                                                  targetSize:thumbnailSize];
            if (resizedImage != nil) {
                [strongSelf.thumbnailCache setObject:resizedImage forKey:cacheKey];
            }
        }
    });
}

- (void)loadThumbnailForClipItem:(RCClipItem *)clipItem
                        cacheKey:(NSString *)cacheKey
                updatingMenuItem:(NSMenuItem *)menuItem
                    numberPrefix:(NSString *)numberPrefix
                       baseTitle:(NSString *)baseTitle {
    if (clipItem.thumbnailPath.length == 0 || cacheKey.length == 0 || menuItem == nil) {
        return;
    }

    NSString *thumbnailPath = [clipItem.thumbnailPath copy];
    NSString *expectedDataHash = [clipItem.dataHash copy] ?: @"";
    NSString *numberPrefixCopy = [numberPrefix copy] ?: @"";
    NSString *baseTitleCopy = [baseTitle copy] ?: @"";
    NSSize thumbnailSize = [self thumbnailPreviewSize];
    __weak typeof(self) weakSelf = self;
    __weak NSMenuItem *weakMenuItem = menuItem;
    dispatch_async(self.thumbnailGenerationQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        NSImage *resizedImage = [strongSelf.thumbnailCache objectForKey:cacheKey];
        if (resizedImage == nil) {
            resizedImage = [strongSelf resizedThumbnailImageAtPath:thumbnailPath targetSize:thumbnailSize];
            if (resizedImage != nil) {
                [strongSelf.thumbnailCache setObject:resizedImage forKey:cacheKey];
            }
        }

        if (resizedImage == nil) {
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            NSMenuItem *strongMenuItem = weakMenuItem;
            if (strongMenuItem == nil) {
                return;
            }

            id representedObject = strongMenuItem.representedObject;
            if (![representedObject isKindOfClass:[NSString class]]
                || ![(NSString *)representedObject isEqualToString:expectedDataHash]) {
                return;
            }

            [strongSelf applyMenuItemTitleForItem:strongMenuItem
                                     numberPrefix:numberPrefixCopy
                                        baseTitle:baseTitleCopy
                                            image:resizedImage];
        });
    });
}

- (nullable NSImage *)resizedThumbnailImageAtPath:(NSString *)thumbnailPath targetSize:(NSSize)targetSize {
    if (thumbnailPath.length == 0) {
        return nil;
    }

    NSImage *thumbnailImage = [[NSImage alloc] initWithContentsOfFile:thumbnailPath];
    if (thumbnailImage == nil) {
        return nil;
    }

    NSImage *resizedImage = [thumbnailImage resizedImageToFitSize:targetSize];
    if (resizedImage == nil) {
        resizedImage = [thumbnailImage resizedImageToSize:targetSize];
    }
    if (resizedImage == nil) {
        return nil;
    }

    resizedImage.template = NO;
    return resizedImage;
}

- (nullable NSImage *)typeIconForClipItem:(RCClipItem *)clipItem {
    NSInteger preferredIconSize = [self integerPreferenceForKey:kRCPrefMenuIconSizeKey defaultValue:16];
    CGFloat iconSide = (CGFloat)MAX(8, preferredIconSize);
    NSSize iconSize = NSMakeSize(iconSide, iconSide);

    NSImage *typeImage = [self primaryTypeIconForType:clipItem.primaryType];
    NSImage *resizedImage = [typeImage resizedImageToFitSize:iconSize];
    if (resizedImage == nil) {
        resizedImage = [typeImage resizedImageToSize:iconSize];
    }
    if (resizedImage != nil) {
        resizedImage.template = YES;
        return resizedImage;
    }

    NSImage *iconCopy = [typeImage copy];
    iconCopy.size = iconSize;
    iconCopy.template = YES;
    return iconCopy;
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

    return [NSString stringWithFormat:@"%lu", (unsigned long)(globalIndex + 1)];
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
        [self handleMissingClipDataForClipItem:clipItem reason:@"empty data path"];
        return;
    }

    RCClipData *clipData = [RCClipData clipDataFromPath:clipItem.dataPath];
    if (clipData == nil) {
        [self handleMissingClipDataForClipItem:clipItem reason:@"missing or unreadable clip data file"];
        return;
    }

    [[RCPasteService shared] pasteClipData:clipData];
}

- (void)selectSnippetMenuItem:(NSMenuItem *)menuItem {
    NSDictionary *selectionInfo = nil;
    if ([menuItem.representedObject isKindOfClass:[NSDictionary class]]) {
        selectionInfo = (NSDictionary *)menuItem.representedObject;
    }

    NSString *folderIdentifier = [self stringValueFromDictionary:selectionInfo
                                                             key:kRCSnippetMenuFolderIdentifierKey
                                                    defaultValue:@""];
    NSString *snippetIdentifier = [self stringValueFromDictionary:selectionInfo
                                                              key:kRCSnippetMenuSnippetIdentifierKey
                                                     defaultValue:@""];
    if (folderIdentifier.length == 0 || snippetIdentifier.length == 0) {
        return;
    }

    NSString *content = [self snippetContentForFolderIdentifier:folderIdentifier snippetIdentifier:snippetIdentifier];
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
        alert.messageText = NSLocalizedString(@"Clear clipboard history?", nil);
        alert.informativeText = NSLocalizedString(@"All saved clips will be removed.", nil);
        [alert addButtonWithTitle:NSLocalizedString(@"Clear", nil)];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];

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
        NSArray<NSString *> *pathsToDelete = [self clipDataFilePathsSnapshotForCurrentHistoryWithDatabaseManager:databaseManager];

        if (![databaseManager deleteAllClipItems]) {
            return;
        }

        [databaseManager performDatabaseOperation:^BOOL(FMDatabase *db) {
            [db executeStatements:@"PRAGMA incremental_vacuum;"];
            [db executeStatements:@"PRAGMA wal_checkpoint(TRUNCATE);"];
            return YES;
        }];

        [self.thumbnailCache removeAllObjects];

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self removeClipDataFilesAtPaths:pathsToDelete];
        });

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

- (void)openSnippetEditor:(NSMenuItem *)sender {
    (void)sender;

    if ([NSApp sendAction:@selector(showSnippetEditor:) to:nil from:self]) {
        return;
    }

    NSBeep();
}

#pragma mark - Helpers

- (NSArray<NSString *> *)clipDataFilePathsSnapshotForCurrentHistoryWithDatabaseManager:(RCDatabaseManager *)databaseManager {
    if (databaseManager == nil) {
        return @[];
    }

    NSInteger count = [databaseManager clipItemCount];
    if (count <= 0) {
        return @[];
    }

    NSArray<NSDictionary *> *clipRows = [databaseManager fetchClipItemsWithLimit:count];
    if (clipRows.count == 0) {
        return @[];
    }

    NSMutableOrderedSet<NSString *> *paths = [NSMutableOrderedSet orderedSet];
    for (NSDictionary *clipRow in clipRows) {
        RCClipItem *clipItem = [[RCClipItem alloc] initWithDictionary:clipRow];
        if (clipItem.dataPath.length > 0) {
            [paths addObject:clipItem.dataPath];
        }
        if (clipItem.thumbnailPath.length > 0) {
            [paths addObject:clipItem.thumbnailPath];
        }
    }

    return paths.array;
}

- (void)removeClipDataFilesAtPaths:(NSArray<NSString *> *)paths {
    NSString *clipDirectoryPath = [RCUtilities clipDataDirectoryPath];
    NSString *expandedPath = [[clipDirectoryPath stringByExpandingTildeInPath] stringByStandardizingPath];
    NSString *canonicalBase = [expandedPath stringByResolvingSymlinksInPath];
    if (canonicalBase.length == 0) {
        return;
    }
    if (![canonicalBase hasSuffix:@"/"]) {
        canonicalBase = [canonicalBase stringByAppendingString:@"/"];
    }

    for (NSString *path in paths) {
        NSString *itemPath = [[path stringByExpandingTildeInPath] stringByStandardizingPath];
        if (itemPath.length == 0) {
            continue;
        }

        NSString *canonicalPath = [itemPath stringByResolvingSymlinksInPath];
        if (![canonicalPath hasPrefix:canonicalBase]) {
            continue;
        }

        [RCPanicEraseService secureOverwriteFileAtPath:itemPath];
        [self removeFileAtPath:itemPath];
    }
}

- (nullable NSString *)snippetContentForFolderIdentifier:(NSString *)folderIdentifier snippetIdentifier:(NSString *)snippetIdentifier {
    if (folderIdentifier.length == 0 || snippetIdentifier.length == 0) {
        return nil;
    }

    NSArray<NSDictionary *> *snippets = [[RCDatabaseManager shared] fetchSnippetsForFolder:folderIdentifier];
    for (NSDictionary *snippet in snippets) {
        NSString *identifier = [self stringValueFromDictionary:snippet key:@"identifier" defaultValue:@""];
        if (![identifier isEqualToString:snippetIdentifier]) {
            continue;
        }

        BOOL enabled = [self boolValueFromDictionary:snippet key:@"enabled" defaultValue:YES];
        if (!enabled) {
            return nil;
        }

        return [self stringValueFromDictionary:snippet key:@"content" defaultValue:@""];
    }

    return nil;
}

- (void)handleMissingClipDataForClipItem:(RCClipItem *)clipItem reason:(NSString *)reason {
    NSString *dataHash = clipItem.dataHash ?: @"";
    NSString *safeReason = reason.length > 0 ? reason : @"unknown reason";

    if (dataHash.length == 0) {
        NSLog(@"[RCMenuManager] Clip data recovery skipped: missing data_hash (%@).", safeReason);
        [self rebuildMenu];
        return;
    }

    BOOL deleted = [[RCDatabaseManager shared] deleteClipItemWithDataHash:dataHash];
    if (!deleted) {
        os_log_error(RCMenuManagerLog(),
                     "Clip data recovery failed: could not delete orphaned row for data_hash=%{private}@ (%{public}@)",
                     dataHash, safeReason);
        [self rebuildMenu];
        return;
    }

    os_log_debug(RCMenuManagerLog(),
                 "Removed orphaned clip row for missing clip data. data_hash=%{private}@ (%{public}@)",
                 dataHash, safeReason);
    [self.thumbnailCache removeAllObjects];
    [self rebuildMenu];
}

- (void)removeAllClipDataFilesFromDisk {
    NSString *clipDirectoryPath = [RCUtilities clipDataDirectoryPath];
    NSString *expandedPath = [[clipDirectoryPath stringByExpandingTildeInPath] stringByStandardizingPath];
    if (expandedPath.length == 0) {
        return;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray<NSString *> *children = [fileManager contentsOfDirectoryAtPath:expandedPath error:nil];
    NSString *canonicalBase = [expandedPath stringByResolvingSymlinksInPath];
    if (canonicalBase.length == 0) {
        return;
    }
    if (![canonicalBase hasSuffix:@"/"]) {
        canonicalBase = [canonicalBase stringByAppendingString:@"/"];
    }
    for (NSString *child in children) {
        if (![self isKnownClipDataFileName:child]) {
            continue;
        }

        NSString *itemPath = [expandedPath stringByAppendingPathComponent:child];
        NSString *canonicalPath = [itemPath stringByResolvingSymlinksInPath];
        if (![canonicalPath hasPrefix:canonicalBase]) {
            continue;
        }

        BOOL isDirectory = NO;
        if (![fileManager fileExistsAtPath:itemPath isDirectory:&isDirectory] || isDirectory) {
            continue;
        }

        [self removeFileAtPath:itemPath];
    }
}

- (BOOL)isKnownClipDataFileName:(NSString *)fileName {
    if (fileName.length == 0) {
        return NO;
    }

    NSString *lowercaseFileName = [fileName lowercaseString];
    NSString *extension = [[fileName pathExtension] lowercaseString];
    return [extension isEqualToString:kRCClipDataFileExtension]
        || [extension isEqualToString:kRCThumbnailFileExtension]
        || [lowercaseFileName hasSuffix:kRCLegacyThumbnailFileSuffix];
}

- (void)removeFileAtPath:(NSString *)path {
    if (path.length == 0) {
        return;
    }

    NSString *expandedPath = [[path stringByExpandingTildeInPath] stringByStandardizingPath];
    if (expandedPath.length == 0) {
        return;
    }

    NSString *clipDirectoryPath = [RCUtilities clipDataDirectoryPath];
    NSString *standardizedClipDirectoryPath = [[clipDirectoryPath stringByExpandingTildeInPath] stringByStandardizingPath];
    if (standardizedClipDirectoryPath.length == 0 || ![expandedPath hasPrefix:standardizedClipDirectoryPath]) {
        return;
    }

    NSString *clipDirectoryPrefix = [standardizedClipDirectoryPath hasSuffix:@"/"]
        ? standardizedClipDirectoryPath
        : [standardizedClipDirectoryPath stringByAppendingString:@"/"];
    BOOL isExactDirectoryPath = [expandedPath isEqualToString:standardizedClipDirectoryPath];
    BOOL isNestedPath = [expandedPath hasPrefix:clipDirectoryPrefix];
    if (!isExactDirectoryPath && !isNestedPath) {
        return;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:expandedPath isDirectory:&isDirectory] || isDirectory) {
        return;
    }

    NSDictionary<NSFileAttributeKey, id> *attributes = [fileManager attributesOfItemAtPath:expandedPath error:nil];
    NSString *fileType = [attributes[NSFileType] isKindOfClass:[NSString class]] ? attributes[NSFileType] : nil;
    if (![fileType isEqualToString:NSFileTypeRegular]) {
        return;
    }

    [RCPanicEraseService secureOverwriteFileAtPath:expandedPath];

    NSError *error = nil;
    BOOL removed = [fileManager removeItemAtPath:expandedPath error:&error];
    if (!removed) {
        os_log_error(RCMenuManagerLog(),
                     "Failed to remove file at %{private}@ (%{private}@)",
                     expandedPath, error.localizedDescription);
    }
}

- (NSString *)truncatedString:(NSString *)string maxLength:(NSInteger)maxLength {
    if (string.length == 0 || maxLength <= 0 || string.length <= (NSUInteger)maxLength) {
        return string ?: @"";
    }

    if (maxLength <= 3) {
        NSRange safeRange = [self composedSafePrefixRangeForString:string maxLength:(NSUInteger)maxLength];
        return [string substringWithRange:safeRange];
    }

    NSUInteger bodyLength = (NSUInteger)(maxLength - 3);
    NSRange safeRange = [self composedSafePrefixRangeForString:string maxLength:bodyLength];
    NSString *truncated = [string substringWithRange:safeRange];
    return [truncated stringByAppendingString:@"..."];
}

- (NSRange)composedSafePrefixRangeForString:(NSString *)string maxLength:(NSUInteger)maxLength {
    if (string.length == 0 || maxLength == 0) {
        return NSMakeRange(0, 0);
    }

    NSUInteger requestedLength = MIN(maxLength, string.length);
    NSRange safeRange = [string rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, requestedLength)];

    while (safeRange.length > maxLength && safeRange.length > 0) {
        NSUInteger adjustedLength = safeRange.length;
        NSRange lastSequenceRange = [string rangeOfComposedCharacterSequenceAtIndex:(adjustedLength - 1)];
        if (lastSequenceRange.location == NSNotFound || lastSequenceRange.location >= adjustedLength) {
            adjustedLength -= 1;
        } else {
            adjustedLength = lastSequenceRange.location;
        }
        safeRange = [string rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, adjustedLength)];
    }

    return safeRange;
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

- (void)clearThumbnailCache {
    [self.thumbnailCache removeAllObjects];
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

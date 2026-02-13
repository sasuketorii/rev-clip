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
#import "RCPasteService.h"
#import "NSColor+HexString.h"
#import "NSImage+Color.h"
#import "NSImage+Resize.h"
#import "RCUtilities.h"

static NSString * const kRCStatusBarIconAssetName = @"StatusBarIcon";
static NSInteger const kRCMaximumNumberedMenuItems = 9;

@interface RCMenuManager () <NSMenuDelegate>

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
        _statusMenu = [self menuWithTitle:@"Revclip"];

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
        if (self.statusItem == nil || self.statusItem.button == nil) {
            return;
        }

        [self rebuildMenuInternal];
        [self.statusItem.button performClick:nil];
    }];
}

- (void)popUpHistoryMenuFromHotKey {
    [self performOnMainThread:^{
        [self applyStatusItemPreference];
        if (self.statusItem == nil || self.statusItem.button == nil) {
            return;
        }

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
        if (self.statusItem == nil || self.statusItem.button == nil) {
            return;
        }

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
        if (self.statusItem == nil || self.statusItem.button == nil) {
            return;
        }

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
    if (menu == nil || self.statusItem == nil || self.statusItem.button == nil) {
        return;
    }

    [self configureMenuForSimpleTransparentBackground:menu];
    NSMenu *originalMenu = self.statusItem.menu ?: self.statusMenu;
    self.statusItem.menu = menu;
    [self.statusItem.button performClick:nil];
    self.statusItem.menu = originalMenu;
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
    if (addClearHistory) {
        [self.statusMenu addItem:[NSMenuItem separatorItem]];

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

- (void)appendClipHistorySectionToMenu:(NSMenu *)menu {
    RCDatabaseManager *databaseManager = [RCDatabaseManager shared];
    NSInteger clipCount = [databaseManager clipItemCount];
    NSArray<NSDictionary *> *clipRows = @[];
    if (clipCount > 0) {
        clipRows = [databaseManager fetchClipItemsWithLimit:clipCount];
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
        snippetItem.representedObject = snippetContent ?: @"";
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

    NSMenuItem *editSnippetsItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Edit Snippets...", nil)
                                                               action:@selector(openSnippetEditor:)
                                                        keyEquivalent:@""];
    editSnippetsItem.target = self;
    [menu addItem:editSnippetsItem];

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
    NSString *menuTitle = [self menuTitleForClipItem:clipItem globalIndex:globalIndex];

    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:menuTitle
                                                  action:@selector(selectClipMenuItem:)
                                           keyEquivalent:@""];
    item.target = self;
    item.representedObject = clipItem.dataHash ?: @"";

    BOOL needsTooltip = [self boolPreferenceForKey:kRCShowToolTipOnMenuItemKey defaultValue:YES];
    BOOL showImagePreview = [self boolPreferenceForKey:kRCShowImageInTheMenuKey defaultValue:YES];
    BOOL showColorPreview = [self boolPreferenceForKey:kRCPrefShowColorPreviewInTheMenu defaultValue:YES];
    BOOL showMenuIcon = [self boolPreferenceForKey:kRCPrefShowIconInTheMenuKey defaultValue:YES];

    BOOL tooltipSatisfied = NO;
    if (needsTooltip && clipItem.title.length > 0) {
        NSInteger maxLength = [self integerPreferenceForKey:kRCMaxLengthOfToolTipKey defaultValue:200];
        item.toolTip = [self truncatedString:clipItem.title maxLength:MAX(1, maxLength)];
        tooltipSatisfied = YES;
    }

    BOOL imageSatisfied = NO;
    if (!clipItem.isColorCode) {
        if (showImagePreview && clipItem.thumbnailPath.length > 0) {
            NSImage *thumbnailImage = [[NSImage alloc] initWithContentsOfFile:clipItem.thumbnailPath];
            if (thumbnailImage != nil) {
                CGFloat thumbnailWidth = (CGFloat)MAX(1, [self integerPreferenceForKey:kRCThumbnailWidthKey defaultValue:100]);
                CGFloat thumbnailHeight = (CGFloat)MAX(1, [self integerPreferenceForKey:kRCThumbnailHeightKey defaultValue:32]);
                NSSize thumbnailSize = NSMakeSize(thumbnailWidth, thumbnailHeight);
                NSImage *resized = [thumbnailImage resizedImageToFitSize:thumbnailSize];
                if (resized == nil) {
                    resized = [thumbnailImage resizedImageToSize:thumbnailSize];
                }
                if (resized != nil) {
                    resized.template = NO;
                    item.image = resized;
                    imageSatisfied = YES;
                }
            }
        }

        if (!imageSatisfied && showMenuIcon) {
            NSImage *iconImage = [self typeIconForClipItem:clipItem];
            if (iconImage != nil) {
                item.image = iconImage;
                imageSatisfied = YES;
            }
        }
    } else if (!showColorPreview && showMenuIcon) {
        NSImage *iconImage = [self typeIconForClipItem:clipItem];
        if (iconImage != nil) {
            item.image = iconImage;
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
                NSInteger maxLength = [self integerPreferenceForKey:kRCMaxLengthOfToolTipKey defaultValue:200];
                item.toolTip = [self truncatedString:toolTip maxLength:MAX(1, maxLength)];
            }
        }

        if (needsClipDataForImage) {
            NSImage *image = [self imageForClipItem:clipItem clipData:clipData];
            if (image != nil) {
                item.image = image;
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
        CGFloat thumbnailWidth = (CGFloat)MAX(1, [self integerPreferenceForKey:kRCThumbnailWidthKey defaultValue:100]);
        CGFloat thumbnailHeight = (CGFloat)MAX(1, [self integerPreferenceForKey:kRCThumbnailHeightKey defaultValue:32]);
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

- (void)openSnippetEditor:(NSMenuItem *)sender {
    (void)sender;

    if ([NSApp sendAction:@selector(showSnippetEditor:) to:nil from:self]) {
        return;
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

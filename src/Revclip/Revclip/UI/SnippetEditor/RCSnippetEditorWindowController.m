//
//  RCSnippetEditorWindowController.m
//  Revpy
//
//  Copyright (c) 2024-2026 Revpy. All rights reserved.
//

#import "RCSnippetEditorWindowController.h"

#import "RCConstants.h"
#import "RCDatabaseManager.h"
#import "FMDB.h"
#import "RCHotKeyService.h"
#import "RCMenuManager.h"
#import "RCSnippetImportExportService.h"

@import UniformTypeIdentifiers;

static NSPasteboardType const kRCSnippetOutlineDragType = @"com.revclip.snippet-outline-item";

static NSString * const kRCSnippetDragTypeFolder = @"folder";
static NSString * const kRCSnippetDragTypeSnippet = @"snippet";

static CGFloat const kRCSnippetEditorWindowWidth = 700.0;
static CGFloat const kRCSnippetEditorWindowHeight = 500.0;
static CGFloat const kRCSnippetEditorMinWidth = 500.0;
static CGFloat const kRCSnippetEditorMinHeight = 400.0;
static CGFloat const kRCSnippetEditorBottomBarHeight = 44.0;
static CGFloat const kRCSnippetEditorLeftPaneWidth = 220.0;

static NSString * const kRCSnippetImportExportExtensionRevclip = @"revclipsnippets";

static UTType *RCSnippetImportExportContentType(void) {
    UTType *contentType = [UTType typeWithFilenameExtension:kRCSnippetImportExportExtensionRevclip];
    return (contentType != nil) ? contentType : UTTypeData;
}

@class RCSnippetFolderNode;

@interface RCSnippetNode : NSObject

@property (nonatomic, weak) RCSnippetFolderNode *parentFolder;
@property (nonatomic, strong) NSMutableDictionary *snippetDictionary;

@end

@implementation RCSnippetNode

@end

@interface RCSnippetFolderNode : NSObject

@property (nonatomic, strong) NSMutableDictionary *folderDictionary;
@property (nonatomic, strong) NSMutableArray<RCSnippetNode *> *snippetNodes;

@end

@implementation RCSnippetFolderNode

@end

@interface RCSnippetEditorWindowController () <NSOutlineViewDataSource, NSOutlineViewDelegate>

@property (nonatomic, strong) NSMutableArray<RCSnippetFolderNode *> *folderNodes;

@property (nonatomic, strong) NSSplitView *splitView;
@property (nonatomic, strong) NSOutlineView *outlineView;
@property (nonatomic, strong) NSTextField *titleField;
@property (nonatomic, strong) NSTextField *contentLabel;
@property (nonatomic, strong) NSScrollView *contentScrollView;
@property (nonatomic, strong) NSTextView *contentTextView;
@property (nonatomic, strong) NSTextField *saveShortcutHintLabel;
@property (nonatomic, strong) NSPopUpButton *addButton;
@property (nonatomic, strong) NSButton *removeButton;
@property (nonatomic, strong) NSButton *enabledToggleButton;
@property (nonatomic, strong) NSButton *importButton;
@property (nonatomic, strong) NSButton *exportButton;
@property (nonatomic, strong) NSButton *saveButton;

@property (nonatomic, assign) BOOL uiBuilt;
@property (nonatomic, assign) BOOL centeredOnFirstShow;
@property (nonatomic, assign) BOOL updatingEditor;

- (NSArray<NSDictionary *> *)fetchAllSnippetRows;
- (NSDictionary<NSString *, NSArray<NSDictionary *> *> *)snippetRowsGroupedByFolderIdentifier:(NSArray<NSDictionary *> *)snippetRows;

@end

@implementation RCSnippetEditorWindowController

+ (instancetype)shared {
    static RCSnippetEditorWindowController *sharedController = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedController = [[self alloc] init];
    });
    return sharedController;
}

- (instancetype)init {
    self = [super initWithWindowNibName:@"RCSnippetEditorWindow"];
    if (self) {
        _folderNodes = [NSMutableArray array];
        _uiBuilt = NO;
        _centeredOnFirstShow = NO;
        _updatingEditor = NO;
    }
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];

    [self configureWindow];
    [self buildInterfaceIfNeeded];
    [self reloadOutlineSelectingFolderIdentifier:nil snippetIdentifier:nil];
}

- (void)showWindow:(id)sender {
    [super showWindow:sender];

    if (!self.centeredOnFirstShow) {
        [self.window center];
        self.centeredOnFirstShow = YES;
    }

    [self.window makeKeyAndOrderFront:sender];
    [NSApp activateIgnoringOtherApps:YES];
    [self reloadOutlineSelectingFolderIdentifier:nil snippetIdentifier:nil];
}

#pragma mark - Window / UI

- (void)configureWindow {
    NSWindow *window = self.window;
    window.title = NSLocalizedString(@"Template Editor", nil);
    window.styleMask = NSWindowStyleMaskTitled
                     | NSWindowStyleMaskClosable
                     | NSWindowStyleMaskMiniaturizable
                     | NSWindowStyleMaskResizable;
    window.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace;
    window.releasedWhenClosed = NO;
    window.minSize = NSMakeSize(kRCSnippetEditorMinWidth, kRCSnippetEditorMinHeight);
    [window setContentSize:NSMakeSize(kRCSnippetEditorWindowWidth, kRCSnippetEditorWindowHeight)];
}

- (void)buildInterfaceIfNeeded {
    if (self.uiBuilt) {
        return;
    }

    NSView *contentView = self.window.contentView;
    if (contentView == nil) {
        return;
    }

    NSRect bounds = contentView.bounds;

    NSView *bottomBar = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, bounds.size.width, kRCSnippetEditorBottomBarHeight)];
    bottomBar.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [contentView addSubview:bottomBar];

    self.splitView = [[NSSplitView alloc] initWithFrame:NSMakeRect(0.0,
                                                                   kRCSnippetEditorBottomBarHeight,
                                                                   bounds.size.width,
                                                                   bounds.size.height - kRCSnippetEditorBottomBarHeight)];
    self.splitView.vertical = YES;
    self.splitView.dividerStyle = NSSplitViewDividerStyleThin;
    self.splitView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [contentView addSubview:self.splitView];

    NSView *leftPane = [[NSView alloc] initWithFrame:NSMakeRect(0.0,
                                                                 0.0,
                                                                 kRCSnippetEditorLeftPaneWidth,
                                                                 self.splitView.bounds.size.height)];
    NSView *rightPane = [[NSView alloc] initWithFrame:NSMakeRect(0.0,
                                                                  0.0,
                                                                  self.splitView.bounds.size.width - kRCSnippetEditorLeftPaneWidth,
                                                                  self.splitView.bounds.size.height)];

    [self.splitView addSubview:leftPane];
    [self.splitView addSubview:rightPane];
    [self.splitView setPosition:kRCSnippetEditorLeftPaneWidth ofDividerAtIndex:0];

    [self buildOutlineInLeftPane:leftPane];
    [self buildEditorInRightPane:rightPane];
    [self buildBottomBarInView:bottomBar];

    self.uiBuilt = YES;
}

- (void)buildOutlineInLeftPane:(NSView *)leftPane {
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:leftPane.bounds];
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;

    self.outlineView = [[NSOutlineView alloc] initWithFrame:scrollView.bounds];
    self.outlineView.delegate = self;
    self.outlineView.dataSource = self;
    self.outlineView.headerView = nil;
    self.outlineView.rowSizeStyle = NSTableViewRowSizeStyleDefault;
    self.outlineView.allowsMultipleSelection = NO;
    self.outlineView.allowsEmptySelection = YES;
    self.outlineView.focusRingType = NSFocusRingTypeNone;

    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"TitleColumn"];
    column.title = NSLocalizedString(@"Snippets", nil);
    column.resizingMask = NSTableColumnAutoresizingMask;
    column.width = leftPane.bounds.size.width;

    [self.outlineView addTableColumn:column];
    self.outlineView.outlineTableColumn = column;

    [self.outlineView registerForDraggedTypes:@[kRCSnippetOutlineDragType]];
    [self.outlineView setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];

    scrollView.documentView = self.outlineView;
    [leftPane addSubview:scrollView];
}

- (void)buildEditorInRightPane:(NSView *)rightPane {
    CGFloat const inset = 16.0;

    NSTextField *titleLabel = [self labelWithString:NSLocalizedString(@"Title:", nil)];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [rightPane addSubview:titleLabel];

    self.titleField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.titleField.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleField.target = self;
    self.titleField.action = @selector(saveButtonClicked:);
    [rightPane addSubview:self.titleField];

    self.contentLabel = [self labelWithString:NSLocalizedString(@"Content:", nil)];
    self.contentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [rightPane addSubview:self.contentLabel];

    self.contentTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 100.0)];
    self.contentTextView.textContainerInset = NSMakeSize(8.0, 8.0);
    self.contentTextView.minSize = NSMakeSize(0.0, 100.0);
    self.contentTextView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    self.contentTextView.verticallyResizable = YES;
    self.contentTextView.horizontallyResizable = NO;
    self.contentTextView.autoresizingMask = NSViewWidthSizable;
    self.contentTextView.usesFindBar = YES;
    self.contentTextView.richText = NO;
    self.contentTextView.allowsUndo = YES;

    self.contentScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.contentScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentScrollView.hasVerticalScroller = YES;
    self.contentScrollView.hasHorizontalScroller = NO;
    self.contentScrollView.borderType = NSBezelBorder;
    self.contentTextView.textContainer.containerSize = NSMakeSize(FLT_MAX, CGFLOAT_MAX);
    self.contentTextView.textContainer.widthTracksTextView = YES;
    self.contentScrollView.documentView = self.contentTextView;
    [rightPane addSubview:self.contentScrollView];

    self.saveShortcutHintLabel = [NSTextField labelWithString:NSLocalizedString(@"Save with ⌘S", nil)];
    self.saveShortcutHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.saveShortcutHintLabel.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular];
    self.saveShortcutHintLabel.textColor = NSColor.secondaryLabelColor;
    [rightPane addSubview:self.saveShortcutHintLabel];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:rightPane.topAnchor constant:inset],
        [titleLabel.leadingAnchor constraintEqualToAnchor:rightPane.leadingAnchor constant:inset],

        [self.titleField.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:6.0],
        [self.titleField.leadingAnchor constraintEqualToAnchor:rightPane.leadingAnchor constant:(inset - 3.0)],
        [self.titleField.trailingAnchor constraintEqualToAnchor:rightPane.trailingAnchor constant:-(inset - 3.0)],

        [self.contentLabel.topAnchor constraintEqualToAnchor:self.titleField.bottomAnchor constant:12.0],
        [self.contentLabel.leadingAnchor constraintEqualToAnchor:rightPane.leadingAnchor constant:inset],

        [self.contentScrollView.topAnchor constraintEqualToAnchor:self.contentLabel.bottomAnchor constant:6.0],
        [self.contentScrollView.leadingAnchor constraintEqualToAnchor:rightPane.leadingAnchor constant:inset],
        [self.contentScrollView.trailingAnchor constraintEqualToAnchor:rightPane.trailingAnchor constant:-inset],
        [self.contentScrollView.heightAnchor constraintGreaterThanOrEqualToConstant:120.0],

        [self.saveShortcutHintLabel.topAnchor constraintEqualToAnchor:self.contentScrollView.bottomAnchor constant:8.0],
        [self.saveShortcutHintLabel.leadingAnchor constraintEqualToAnchor:rightPane.leadingAnchor constant:inset],
        [self.saveShortcutHintLabel.trailingAnchor constraintLessThanOrEqualToAnchor:rightPane.trailingAnchor constant:-inset],
        [self.saveShortcutHintLabel.bottomAnchor constraintEqualToAnchor:rightPane.bottomAnchor constant:-inset],
    ]];
}

- (void)buildBottomBarInView:(NSView *)bottomBar {
    self.addButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES];
    self.addButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.addButton removeAllItems];
    [self.addButton addItemWithTitle:@"+"];

    NSMenu *menu = self.addButton.menu;
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *addFolderItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Add Folder", nil)
                                                           action:@selector(addFolderMenuItemSelected:)
                                                    keyEquivalent:@""];
    addFolderItem.target = self;
    [menu addItem:addFolderItem];

    NSMenuItem *addSnippetItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Add Snippet", nil)
                                                            action:@selector(addSnippetMenuItemSelected:)
                                                     keyEquivalent:@""];
    addSnippetItem.target = self;
    [menu addItem:addSnippetItem];

    [bottomBar addSubview:self.addButton];

    self.removeButton = [NSButton buttonWithTitle:@"-"
                                           target:self
                                           action:@selector(removeSelectedItem:)];
    self.removeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [bottomBar addSubview:self.removeButton];

    self.enabledToggleButton = [self actionButtonWithTitle:@""
                                                 symbolName:@"eye"
                                                     action:@selector(toggleSelectedItemEnabled:)];
    self.enabledToggleButton.imagePosition = NSImageOnly;
    self.enabledToggleButton.toolTip = NSLocalizedString(@"Enable/Disable", nil);
    [bottomBar addSubview:self.enabledToggleButton];

    self.importButton = [self actionButtonWithTitle:NSLocalizedString(@"Import", nil)
                                         symbolName:@"square.and.arrow.down"
                                             action:@selector(importButtonClicked:)];
    [bottomBar addSubview:self.importButton];

    self.exportButton = [self actionButtonWithTitle:NSLocalizedString(@"Export", nil)
                                         symbolName:@"square.and.arrow.up"
                                             action:@selector(exportButtonClicked:)];
    [bottomBar addSubview:self.exportButton];

    self.saveButton = [NSButton buttonWithTitle:NSLocalizedString(@"Save", nil)
                                         target:self
                                         action:@selector(saveButtonClicked:)];
    self.saveButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.saveButton.bezelStyle = NSBezelStyleRounded;
    self.saveButton.keyEquivalent = @"s";
    self.saveButton.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [bottomBar addSubview:self.saveButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.addButton.leadingAnchor constraintEqualToAnchor:bottomBar.leadingAnchor constant:12.0],
        [self.addButton.centerYAnchor constraintEqualToAnchor:bottomBar.centerYAnchor],
        [self.addButton.widthAnchor constraintEqualToConstant:42.0],

        [self.removeButton.leadingAnchor constraintEqualToAnchor:self.addButton.trailingAnchor constant:8.0],
        [self.removeButton.centerYAnchor constraintEqualToAnchor:bottomBar.centerYAnchor],
        [self.removeButton.widthAnchor constraintEqualToConstant:32.0],

        [self.enabledToggleButton.leadingAnchor constraintEqualToAnchor:self.removeButton.trailingAnchor constant:10.0],
        [self.enabledToggleButton.centerYAnchor constraintEqualToAnchor:bottomBar.centerYAnchor],
        [self.enabledToggleButton.widthAnchor constraintEqualToConstant:36.0],

        [self.importButton.leadingAnchor constraintEqualToAnchor:self.enabledToggleButton.trailingAnchor constant:8.0],
        [self.importButton.centerYAnchor constraintEqualToAnchor:bottomBar.centerYAnchor],
        [self.importButton.widthAnchor constraintEqualToConstant:104.0],

        [self.exportButton.leadingAnchor constraintEqualToAnchor:self.importButton.trailingAnchor constant:8.0],
        [self.exportButton.centerYAnchor constraintEqualToAnchor:bottomBar.centerYAnchor],
        [self.exportButton.widthAnchor constraintEqualToConstant:116.0],

        [self.saveButton.trailingAnchor constraintEqualToAnchor:bottomBar.trailingAnchor constant:-12.0],
        [self.saveButton.centerYAnchor constraintEqualToAnchor:bottomBar.centerYAnchor],
        [self.saveButton.widthAnchor constraintEqualToConstant:80.0],
    ]];
}

- (NSTextField *)labelWithString:(NSString *)stringValue {
    NSTextField *label = [NSTextField labelWithString:stringValue ?: @""];
    label.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
    return label;
}

- (NSButton *)actionButtonWithTitle:(NSString *)title
                         symbolName:(NSString *)symbolName
                             action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title ?: @""
                                          target:self
                                          action:action];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bezelStyle = NSBezelStyleRounded;

    if (@available(macOS 11.0, *)) {
        NSImage *symbolImage = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:title];
        if (symbolImage != nil) {
            button.image = symbolImage;
            button.imagePosition = NSImageLeading;
        }
    }

    return button;
}

#pragma mark - Data Load

- (void)reloadOutlineSelectingFolderIdentifier:(NSString *)folderIdentifier snippetIdentifier:(NSString *)snippetIdentifier {
    [self.folderNodes removeAllObjects];

    NSArray<NSDictionary *> *allSnippetRows = [self fetchAllSnippetRows];
    NSDictionary<NSString *, NSArray<NSDictionary *> *> *snippetRowsByFolderIdentifier = [self snippetRowsGroupedByFolderIdentifier:allSnippetRows];

    NSArray<NSDictionary *> *folders = [[RCDatabaseManager shared] fetchAllSnippetFolders];
    for (NSDictionary *folder in folders) {
        RCSnippetFolderNode *folderNode = [[RCSnippetFolderNode alloc] init];
        folderNode.folderDictionary = [folder mutableCopy];
        folderNode.snippetNodes = [NSMutableArray array];

        NSString *identifier = [self stringValueFromDictionary:folderNode.folderDictionary
                                                           key:@"identifier"
                                                  defaultValue:@""];
        if (identifier.length > 0) {
            NSArray<NSDictionary *> *snippetRows = snippetRowsByFolderIdentifier[identifier];
            for (NSDictionary *snippet in snippetRows) {
                RCSnippetNode *node = [[RCSnippetNode alloc] init];
                node.parentFolder = folderNode;
                node.snippetDictionary = [snippet mutableCopy];
                [folderNode.snippetNodes addObject:node];
            }
        }

        [self.folderNodes addObject:folderNode];
    }

    [self.outlineView reloadData];
    [self expandAllFolders];

    id itemToSelect = nil;
    if (snippetIdentifier.length > 0) {
        itemToSelect = [self snippetNodeForIdentifier:snippetIdentifier];
    }
    if (itemToSelect == nil && folderIdentifier.length > 0) {
        itemToSelect = [self folderNodeForIdentifier:folderIdentifier];
    }
    if (itemToSelect == nil && self.folderNodes.count > 0) {
        itemToSelect = self.folderNodes.firstObject;
    }

    [self selectItem:itemToSelect];
    [self refreshEditorForSelection];
}

- (NSArray<NSDictionary *> *)fetchAllSnippetRows {
    RCDatabaseManager *databaseManager = [RCDatabaseManager shared];
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];

    [databaseManager performTransaction:^BOOL(FMDatabase *db, BOOL *rollback) {
        (void)rollback;

        FMResultSet *resultSet = [db executeQuery:@"SELECT id, identifier, folder_id, snippet_index, enabled, title, content FROM snippets ORDER BY folder_id ASC, snippet_index ASC, id ASC"];
        if (resultSet == nil) {
            NSLog(@"[Revpy] Failed to fetch snippets in a single query for snippet editor reload.");
            return YES;
        }

        while ([resultSet next]) {
            [rows addObject:@{
                @"id": @([resultSet longLongIntForColumn:@"id"]),
                @"identifier": [resultSet stringForColumn:@"identifier"] ?: @"",
                @"folder_id": [resultSet stringForColumn:@"folder_id"] ?: @"",
                @"snippet_index": @([resultSet longLongIntForColumn:@"snippet_index"]),
                @"enabled": @([resultSet boolForColumn:@"enabled"]),
                @"title": [resultSet stringForColumn:@"title"] ?: @"",
                @"content": [resultSet stringForColumn:@"content"] ?: @"",
            }];
        }

        [resultSet close];
        return YES;
    }];

    return [rows copy];
}

- (NSDictionary<NSString *, NSArray<NSDictionary *> *> *)snippetRowsGroupedByFolderIdentifier:(NSArray<NSDictionary *> *)snippetRows {
    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *groupedRows = [NSMutableDictionary dictionary];

    for (NSDictionary *row in snippetRows) {
        NSString *folderIdentifier = [self stringValueFromDictionary:row key:@"folder_id" defaultValue:@""];
        if (folderIdentifier.length == 0) {
            continue;
        }

        NSMutableArray<NSDictionary *> *rowsForFolder = groupedRows[folderIdentifier];
        if (rowsForFolder == nil) {
            rowsForFolder = [NSMutableArray array];
            groupedRows[folderIdentifier] = rowsForFolder;
        }

        [rowsForFolder addObject:row];
    }

    NSMutableDictionary<NSString *, NSArray<NSDictionary *> *> *result = [NSMutableDictionary dictionaryWithCapacity:groupedRows.count];
    for (NSString *folderIdentifier in groupedRows) {
        result[folderIdentifier] = [groupedRows[folderIdentifier] copy];
    }
    return [result copy];
}

- (void)expandAllFolders {
    for (RCSnippetFolderNode *folderNode in self.folderNodes) {
        [self.outlineView expandItem:folderNode];
    }
}

#pragma mark - Selection

- (nullable id)selectedItem {
    NSInteger row = self.outlineView.selectedRow;
    if (row < 0) {
        return nil;
    }
    return [self.outlineView itemAtRow:row];
}

- (nullable RCSnippetFolderNode *)selectedFolderNode {
    id selectedItem = [self selectedItem];
    if ([selectedItem isKindOfClass:[RCSnippetFolderNode class]]) {
        return (RCSnippetFolderNode *)selectedItem;
    }

    if ([selectedItem isKindOfClass:[RCSnippetNode class]]) {
        return ((RCSnippetNode *)selectedItem).parentFolder;
    }

    return nil;
}

- (void)selectItem:(id)item {
    if (item == nil) {
        [self.outlineView deselectAll:nil];
        return;
    }

    NSInteger row = [self.outlineView rowForItem:item];
    if (row < 0) {
        [self.outlineView deselectAll:nil];
        return;
    }

    [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    [self.outlineView scrollRowToVisible:row];
}

- (void)refreshEditorForSelection {
    id selectedItem = [self selectedItem];

    self.updatingEditor = YES;

    BOOL hasSelection = (selectedItem != nil);
    self.titleField.enabled = hasSelection;
    self.saveButton.enabled = hasSelection;
    self.removeButton.enabled = hasSelection;
    self.enabledToggleButton.enabled = hasSelection;

    if (!hasSelection) {
        self.titleField.stringValue = @"";
        self.contentTextView.string = @"";
        self.contentLabel.hidden = NO;
        self.contentScrollView.hidden = NO;
        self.saveShortcutHintLabel.hidden = YES;
        self.contentTextView.editable = NO;
        [self updateEnabledToggleButtonForItem:nil];
        self.updatingEditor = NO;
        return;
    }

    if ([selectedItem isKindOfClass:[RCSnippetFolderNode class]]) {
        RCSnippetFolderNode *folderNode = (RCSnippetFolderNode *)selectedItem;
        self.titleField.stringValue = [self stringValueFromDictionary:folderNode.folderDictionary
                                                                   key:@"title"
                                                          defaultValue:@""];

        self.contentLabel.hidden = YES;
        self.contentScrollView.hidden = YES;
        self.saveShortcutHintLabel.hidden = YES;
        self.contentTextView.editable = NO;
        [self updateEnabledToggleButtonForItem:folderNode];
        self.updatingEditor = NO;
        return;
    }

    RCSnippetNode *snippetNode = (RCSnippetNode *)selectedItem;
    self.titleField.stringValue = [self stringValueFromDictionary:snippetNode.snippetDictionary
                                                               key:@"title"
                                                      defaultValue:@""];
    self.contentTextView.string = [self stringValueFromDictionary:snippetNode.snippetDictionary
                                                              key:@"content"
                                                     defaultValue:@""];

    self.contentLabel.hidden = NO;
    self.contentScrollView.hidden = NO;
    self.saveShortcutHintLabel.hidden = NO;
    self.contentTextView.editable = YES;
    [self updateEnabledToggleButtonForItem:snippetNode];

    self.updatingEditor = NO;
}

#pragma mark - Actions

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (event.type == NSEventTypeKeyDown) {
        NSEventModifierFlags flags = (event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask);
        NSString *pressedKey = event.charactersIgnoringModifiers.lowercaseString ?: @"";
        if (flags == NSEventModifierFlagCommand && [pressedKey isEqualToString:@"s"]) {
            if (self.saveButton == nil || !self.saveButton.enabled || [self selectedItem] == nil) {
                return NO;
            }
            return [self saveButtonClicked:self.saveButton];
        }
    }

    return [super performKeyEquivalent:event];
}

- (BOOL)saveButtonClicked:(id)sender {
    (void)sender;

    if (self.updatingEditor) {
        return NO;
    }

    id selectedItem = [self selectedItem];
    if (selectedItem == nil) {
        return NO;
    }

    if ([selectedItem isKindOfClass:[RCSnippetFolderNode class]]) {
        RCSnippetFolderNode *folderNode = (RCSnippetFolderNode *)selectedItem;
        NSString *title = [self normalizedTitleFromField:self.titleField fallback:NSLocalizedString(@"Untitled Folder", nil)];
        NSString *folderIdentifier = [self stringValueFromDictionary:folderNode.folderDictionary
                                                                 key:@"identifier"
                                                        defaultValue:@""];

        NSMutableDictionary *updatedFolderDictionary = [folderNode.folderDictionary mutableCopy];
        updatedFolderDictionary[@"title"] = title;
        BOOL updated = [[RCDatabaseManager shared] updateSnippetFolder:updatedFolderDictionary];
        if (updated) {
            folderNode.folderDictionary = updatedFolderDictionary;
            [self.outlineView reloadItem:folderNode reloadChildren:NO];
            [[RCMenuManager shared] rebuildMenu];
            [self flashSaveSuccess];
        } else {
            [self reloadOutlineSelectingFolderIdentifier:folderIdentifier snippetIdentifier:nil];
            NSBeep();
        }
        return updated;
    }

    RCSnippetNode *snippetNode = (RCSnippetNode *)selectedItem;
    NSString *title = [self normalizedTitleFromField:self.titleField fallback:NSLocalizedString(@"Untitled Snippet", nil)];
    NSString *content = [self.contentTextView.string copy] ?: @"";
    NSString *folderIdentifier = [self stringValueFromDictionary:snippetNode.parentFolder.folderDictionary
                                                             key:@"identifier"
                                                    defaultValue:@""];
    NSString *snippetIdentifier = [self stringValueFromDictionary:snippetNode.snippetDictionary
                                                              key:@"identifier"
                                                     defaultValue:@""];

    NSMutableDictionary *updatedSnippetDictionary = [snippetNode.snippetDictionary mutableCopy];
    updatedSnippetDictionary[@"title"] = title;
    updatedSnippetDictionary[@"content"] = content;

    BOOL updated = [[RCDatabaseManager shared] updateSnippet:updatedSnippetDictionary];
    if (updated) {
        snippetNode.snippetDictionary = updatedSnippetDictionary;
        [self.outlineView reloadItem:snippetNode reloadChildren:NO];
        [[RCMenuManager shared] rebuildMenu];
        [self flashSaveSuccess];
    } else {
        [self reloadOutlineSelectingFolderIdentifier:folderIdentifier snippetIdentifier:snippetIdentifier];
        NSBeep();
    }
    return updated;
}

- (void)addFolderMenuItemSelected:(id)sender {
    (void)sender;

    NSString *identifier = NSUUID.UUID.UUIDString;
    NSDictionary *folderDict = @{
        @"identifier": identifier,
        @"folder_index": @([self nextFolderIndexValue]),
        @"enabled": @1,
        @"title": NSLocalizedString(@"New Folder", nil),
    };

    BOOL inserted = [[RCDatabaseManager shared] insertSnippetFolder:folderDict];
    if (!inserted) {
        NSBeep();
        return;
    }

    [self reloadOutlineSelectingFolderIdentifier:identifier snippetIdentifier:nil];
    [[RCMenuManager shared] rebuildMenu];
}

- (void)addSnippetMenuItemSelected:(id)sender {
    (void)sender;

    RCSnippetFolderNode *targetFolder = [self selectedFolderNode];
    if (targetFolder == nil) {
        if (self.folderNodes.count == 0) {
            [self addFolderMenuItemSelected:nil];
            targetFolder = self.folderNodes.firstObject;
        } else {
            targetFolder = self.folderNodes.firstObject;
        }
    }

    if (targetFolder == nil) {
        NSBeep();
        return;
    }

    NSString *folderIdentifier = [self stringValueFromDictionary:targetFolder.folderDictionary
                                                             key:@"identifier"
                                                    defaultValue:@""];
    if (folderIdentifier.length == 0) {
        NSBeep();
        return;
    }

    NSString *snippetIdentifier = NSUUID.UUID.UUIDString;
    NSDictionary *snippetDict = @{
        @"identifier": snippetIdentifier,
        @"snippet_index": @([self nextSnippetIndexValueInFolder:targetFolder]),
        @"enabled": @1,
        @"title": NSLocalizedString(@"New Snippet", nil),
        @"content": @"",
    };

    BOOL inserted = [[RCDatabaseManager shared] insertSnippet:snippetDict inFolder:folderIdentifier];
    if (!inserted) {
        NSBeep();
        return;
    }

    [self reloadOutlineSelectingFolderIdentifier:folderIdentifier snippetIdentifier:snippetIdentifier];
    [[RCMenuManager shared] rebuildMenu];
}

- (void)removeSelectedItem:(id)sender {
    (void)sender;

    id selectedItem = [self selectedItem];
    if (selectedItem == nil) {
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:NSLocalizedString(@"Delete", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];

    void (^deleteHandler)(void) = nil;

    if ([selectedItem isKindOfClass:[RCSnippetFolderNode class]]) {
        RCSnippetFolderNode *folderNode = (RCSnippetFolderNode *)selectedItem;
        NSString *identifier = [self stringValueFromDictionary:folderNode.folderDictionary
                                                           key:@"identifier"
                                                  defaultValue:@""];
        NSString *folderTitle = [self stringValueFromDictionary:folderNode.folderDictionary
                                                            key:@"title"
                                                   defaultValue:NSLocalizedString(@"Untitled Folder", nil)];
        if (identifier.length == 0) {
            return;
        }

        alert.messageText = NSLocalizedString(@"Delete this folder and all its snippets?", nil);
        alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"Target folder: %@", nil), folderTitle];

        deleteHandler = ^{
            BOOL deleted = [[RCDatabaseManager shared] deleteSnippetFolder:identifier];
            if (!deleted) {
                NSBeep();
                return;
            }

            [[RCHotKeyService shared] unregisterSnippetFolderHotKey:identifier];
            [self reloadOutlineSelectingFolderIdentifier:nil snippetIdentifier:nil];
            if (![self persistFolderOrderFromCurrentTree]) {
                NSLog(@"[Revpy] Failed to persist folder order after folder deletion. folderIdentifier=%@",
                      identifier);
            }
            [[RCMenuManager shared] rebuildMenu];
        };
    } else if ([selectedItem isKindOfClass:[RCSnippetNode class]]) {
        RCSnippetNode *snippetNode = (RCSnippetNode *)selectedItem;
        NSString *snippetIdentifier = [self stringValueFromDictionary:snippetNode.snippetDictionary
                                                                  key:@"identifier"
                                                         defaultValue:@""];
        NSString *folderIdentifier = [self stringValueFromDictionary:snippetNode.parentFolder.folderDictionary
                                                                 key:@"identifier"
                                                        defaultValue:@""];
        NSString *snippetTitle = [self stringValueFromDictionary:snippetNode.snippetDictionary
                                                             key:@"title"
                                                    defaultValue:NSLocalizedString(@"Untitled Snippet", nil)];
        if (snippetIdentifier.length == 0) {
            return;
        }

        alert.messageText = NSLocalizedString(@"Delete this snippet?", nil);
        alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"Target snippet: %@", nil), snippetTitle];

        deleteHandler = ^{
            BOOL deleted = [[RCDatabaseManager shared] deleteSnippet:snippetIdentifier];
            if (!deleted) {
                NSBeep();
                return;
            }

            [self reloadOutlineSelectingFolderIdentifier:folderIdentifier snippetIdentifier:nil];
            RCSnippetFolderNode *folderNode = [self folderNodeForIdentifier:folderIdentifier];
            if (folderNode != nil) {
                if (![self persistSnippetOrderForFolder:folderNode]) {
                    NSLog(@"[Revpy] Failed to persist snippet order after snippet deletion. folderIdentifier=%@",
                          folderIdentifier);
                }
            }
            [[RCMenuManager shared] rebuildMenu];
        };
    } else {
        return;
    }

    NSWindow *window = self.window;
    if (window != nil) {
        [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
            if (returnCode == NSAlertFirstButtonReturn && deleteHandler != nil) {
                deleteHandler();
            }
        }];
        return;
    }

    if ([alert runModal] == NSAlertFirstButtonReturn && deleteHandler != nil) {
        deleteHandler();
    }
}

- (void)toggleSelectedItemEnabled:(id)sender {
    (void)sender;

    id selectedItem = [self selectedItem];
    if (selectedItem == nil) {
        return;
    }

    BOOL currentEnabled = [self isItemEnabled:selectedItem];
    BOOL nextEnabled = !currentEnabled;
    NSNumber *nextEnabledNumber = @(nextEnabled);
    BOOL updated = NO;

    if ([selectedItem isKindOfClass:[RCSnippetFolderNode class]]) {
        RCSnippetFolderNode *folderNode = (RCSnippetFolderNode *)selectedItem;
        NSMutableDictionary *updatedFolderDictionary = [folderNode.folderDictionary mutableCopy];
        updatedFolderDictionary[@"enabled"] = nextEnabledNumber;
        updated = [[RCDatabaseManager shared] updateSnippetFolder:updatedFolderDictionary];
        if (updated) {
            folderNode.folderDictionary[@"enabled"] = nextEnabledNumber;
            [self.outlineView reloadItem:folderNode reloadChildren:YES];
            [self updateEnabledToggleButtonForItem:folderNode];
        } else {
            NSString *folderIdentifier = [self stringValueFromDictionary:folderNode.folderDictionary
                                                                     key:@"identifier"
                                                            defaultValue:@"<unknown-folder>"];
            NSLog(@"[Revpy] Failed to update snippet folder enabled state. folderIdentifier=%@, enabled=%@",
                  folderIdentifier,
                  nextEnabledNumber);
        }
    } else if ([selectedItem isKindOfClass:[RCSnippetNode class]]) {
        RCSnippetNode *snippetNode = (RCSnippetNode *)selectedItem;
        NSMutableDictionary *updatedSnippetDictionary = [snippetNode.snippetDictionary mutableCopy];
        updatedSnippetDictionary[@"enabled"] = nextEnabledNumber;
        updated = [[RCDatabaseManager shared] updateSnippet:updatedSnippetDictionary];
        if (updated) {
            snippetNode.snippetDictionary[@"enabled"] = nextEnabledNumber;
            [self.outlineView reloadItem:snippetNode reloadChildren:NO];
            [self updateEnabledToggleButtonForItem:snippetNode];
        } else {
            NSString *snippetIdentifier = [self stringValueFromDictionary:snippetNode.snippetDictionary
                                                                       key:@"identifier"
                                                              defaultValue:@"<unknown-snippet>"];
            NSLog(@"[Revpy] Failed to update snippet enabled state. snippetIdentifier=%@, enabled=%@",
                  snippetIdentifier,
                  nextEnabledNumber);
        }
    }

    if (!updated) {
        NSBeep();
        return;
    }

    [[RCHotKeyService shared] reloadFolderHotKeys];
    [[RCMenuManager shared] rebuildMenu];
}

- (void)importButtonClicked:(id)sender {
    (void)sender;

    NSURL *defaultClipyURL = [self defaultClipySnippetsFileURL];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *importURL = nil;

    if (defaultClipyURL != nil && [fileManager fileExistsAtPath:defaultClipyURL.path]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleInformational;
        alert.messageText = NSLocalizedString(@"Import Source", nil);
        alert.informativeText = NSLocalizedString(@"Choose import source.", nil);
        [alert addButtonWithTitle:NSLocalizedString(@"Import from Clipy Default File", nil)];
        [alert addButtonWithTitle:NSLocalizedString(@"Choose File...", nil)];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];

        NSModalResponse response = [alert runModal];
        if (response == NSAlertFirstButtonReturn) {
            importURL = defaultClipyURL;
        } else if (response == NSAlertSecondButtonReturn) {
            importURL = [self chooseImportFileURLWithDefaultDirectoryURL:[defaultClipyURL URLByDeletingLastPathComponent]];
        } else {
            return;
        }
    } else {
        importURL = [self chooseImportFileURLWithDefaultDirectoryURL:[defaultClipyURL URLByDeletingLastPathComponent]];
    }

    [self performImportFromURL:importURL];
}

- (void)performImportFromURL:(NSURL *)importURL {
    if (importURL == nil) {
        return;
    }

    NSError *importError = nil;
    BOOL imported = [[RCSnippetImportExportService shared] importSnippetsFromURL:importURL merge:YES error:&importError];
    if (!imported) {
        [self presentSnippetImportExportError:importError title:NSLocalizedString(@"Failed to Import Snippets", nil)];
        return;
    }

    [self reloadOutlineSelectingFolderIdentifier:nil snippetIdentifier:nil];
    [[RCHotKeyService shared] reloadFolderHotKeys];
    [[RCMenuManager shared] rebuildMenu];
}

- (void)exportButtonClicked:(id)sender {
    (void)sender;

    [self saveButtonClicked:nil];

    id selectedItem = [self selectedItem];
    BOOL exportSelectedOnly = NO;

    if (selectedItem != nil) {
        NSAlert *scopeAlert = [[NSAlert alloc] init];
        scopeAlert.alertStyle = NSAlertStyleInformational;
        scopeAlert.messageText = NSLocalizedString(@"Export Scope", nil);
        scopeAlert.informativeText = NSLocalizedString(@"Choose what to export.", nil);
        [scopeAlert addButtonWithTitle:NSLocalizedString(@"Export Selected Item", nil)];
        [scopeAlert addButtonWithTitle:NSLocalizedString(@"Export All Snippets", nil)];
        [scopeAlert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];

        NSModalResponse scopeResponse = [scopeAlert runModal];
        if (scopeResponse == NSAlertFirstButtonReturn) {
            exportSelectedOnly = YES;
        } else if (scopeResponse == NSAlertSecondButtonReturn) {
            exportSelectedOnly = NO;
        } else {
            return;
        }
    }

    NSString *baseName = exportSelectedOnly ? [self exportBaseFileNameForItem:selectedItem] : @"snippets";
    NSString *defaultFileName = [[self sanitizedFileNameComponent:baseName] stringByAppendingPathExtension:kRCSnippetImportExportExtensionRevclip];

    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.canCreateDirectories = YES;
    panel.allowedContentTypes = @[RCSnippetImportExportContentType()];
    panel.nameFieldStringValue = defaultFileName;

    NSModalResponse saveResponse = [panel runModal];
    if (saveResponse != NSModalResponseOK || panel.URL == nil) {
        return;
    }

    NSURL *parentDirectory = [panel.URL URLByDeletingLastPathComponent];
    if (parentDirectory != nil) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:parentDirectory.path]) {
            NSError *dirError = nil;
            if (![fileManager createDirectoryAtURL:parentDirectory withIntermediateDirectories:YES attributes:nil error:&dirError]) {
                [self presentSnippetImportExportError:dirError title:NSLocalizedString(@"Failed to Export Snippets", nil)];
                return;
            }
        }
    }

    NSError *exportError = nil;
    BOOL exported = NO;
    if (exportSelectedOnly) {
        NSArray<NSDictionary *> *folders = [self folderDictionariesForExportItem:selectedItem];
        exported = [[RCSnippetImportExportService shared] exportFolders:folders toURL:panel.URL error:&exportError];
    } else {
        exported = [[RCSnippetImportExportService shared] exportSnippetsToURL:panel.URL error:&exportError];
    }

    if (!exported) {
        [self presentSnippetImportExportError:exportError title:NSLocalizedString(@"Failed to Export Snippets", nil)];
    }
}

#pragma mark - OutlineView Data Source

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    (void)outlineView;

    if (item == nil) {
        return (NSInteger)self.folderNodes.count;
    }

    if ([item isKindOfClass:[RCSnippetFolderNode class]]) {
        return (NSInteger)((RCSnippetFolderNode *)item).snippetNodes.count;
    }

    return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    (void)outlineView;

    if (index < 0) {
        return nil;
    }

    if (item == nil) {
        if ((NSUInteger)index >= self.folderNodes.count) {
            return nil;
        }
        return self.folderNodes[(NSUInteger)index];
    }

    if ([item isKindOfClass:[RCSnippetFolderNode class]]) {
        NSArray<RCSnippetNode *> *snippetNodes = ((RCSnippetFolderNode *)item).snippetNodes;
        if ((NSUInteger)index >= snippetNodes.count) {
            return nil;
        }
        return snippetNodes[(NSUInteger)index];
    }

    return nil;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    (void)outlineView;
    return [item isKindOfClass:[RCSnippetFolderNode class]];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pasteboard {
    (void)outlineView;

    if (items.count != 1) {
        return NO;
    }

    NSDictionary *dragPayload = [self dragPayloadForItem:items.firstObject];
    if (dragPayload == nil) {
        return NO;
    }

    [pasteboard declareTypes:@[kRCSnippetOutlineDragType] owner:self];
    return [pasteboard setPropertyList:dragPayload forType:kRCSnippetOutlineDragType];
}

- (NSDragOperation)outlineView:(NSOutlineView *)outlineView
                  validateDrop:(id<NSDraggingInfo>)info
                   proposedItem:(id)item
             proposedChildIndex:(NSInteger)index {
    NSDictionary *dragPayload = [self dragPayloadFromDraggingInfo:info];
    if (dragPayload == nil) {
        return NSDragOperationNone;
    }

    NSString *type = [self stringValueFromDictionary:dragPayload key:@"type" defaultValue:@""];

    if ([type isEqualToString:kRCSnippetDragTypeFolder]) {
        if (item != nil) {
            return NSDragOperationNone;
        }

        NSInteger dropIndex = index;
        if (dropIndex == NSOutlineViewDropOnItemIndex || dropIndex < 0) {
            dropIndex = (NSInteger)self.folderNodes.count;
        }
        [outlineView setDropItem:nil dropChildIndex:dropIndex];
        return NSDragOperationMove;
    }

    if (![type isEqualToString:kRCSnippetDragTypeSnippet]) {
        return NSDragOperationNone;
    }

    RCSnippetFolderNode *targetFolder = nil;
    NSInteger dropIndex = index;

    if ([item isKindOfClass:[RCSnippetFolderNode class]]) {
        targetFolder = (RCSnippetFolderNode *)item;
        if (dropIndex == NSOutlineViewDropOnItemIndex || dropIndex < 0) {
            dropIndex = (NSInteger)targetFolder.snippetNodes.count;
        }
    } else if ([item isKindOfClass:[RCSnippetNode class]]) {
        RCSnippetNode *targetSnippet = (RCSnippetNode *)item;
        targetFolder = targetSnippet.parentFolder;
        NSUInteger targetSnippetIndex = [targetFolder.snippetNodes indexOfObjectIdenticalTo:targetSnippet];
        dropIndex = (targetSnippetIndex == NSNotFound) ? (NSInteger)targetFolder.snippetNodes.count : (NSInteger)targetSnippetIndex;
    } else {
        return NSDragOperationNone;
    }

    [outlineView setDropItem:targetFolder dropChildIndex:dropIndex];
    return NSDragOperationMove;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView
         acceptDrop:(id<NSDraggingInfo>)info
               item:(id)item
         childIndex:(NSInteger)index {
    NSDictionary *dragPayload = [self dragPayloadFromDraggingInfo:info];
    if (dragPayload == nil) {
        return NO;
    }

    NSString *type = [self stringValueFromDictionary:dragPayload key:@"type" defaultValue:@""];
    NSString *identifier = [self stringValueFromDictionary:dragPayload key:@"identifier" defaultValue:@""];
    if (identifier.length == 0) {
        return NO;
    }

    if ([type isEqualToString:kRCSnippetDragTypeFolder]) {
        RCSnippetFolderNode *sourceFolder = [self folderNodeForIdentifier:identifier];
        if (sourceFolder == nil) {
            return NO;
        }

        NSUInteger sourceIndex = [self.folderNodes indexOfObjectIdenticalTo:sourceFolder];
        if (sourceIndex == NSNotFound) {
            return NO;
        }

        NSInteger targetIndex = index;
        if (targetIndex < 0 || targetIndex > (NSInteger)self.folderNodes.count) {
            targetIndex = (NSInteger)self.folderNodes.count;
        }

        if ((NSUInteger)targetIndex > sourceIndex) {
            targetIndex--;
        }
        if (targetIndex < 0) {
            targetIndex = 0;
        }

        [self.folderNodes removeObjectAtIndex:sourceIndex];
        [self.folderNodes insertObject:sourceFolder atIndex:(NSUInteger)targetIndex];

        BOOL allUpdatesSucceeded = [self persistFolderOrderFromCurrentTree];
        if (!allUpdatesSucceeded) {
            [self reloadOutlineSelectingFolderIdentifier:nil snippetIdentifier:nil];
            return NO;
        }

        [outlineView reloadData];
        [self expandAllFolders];
        [self selectItem:sourceFolder];
        [[RCMenuManager shared] rebuildMenu];
        return YES;
    }

    if (![type isEqualToString:kRCSnippetDragTypeSnippet]) {
        return NO;
    }

    RCSnippetNode *sourceSnippet = [self snippetNodeForIdentifier:identifier];
    if (sourceSnippet == nil) {
        return NO;
    }

    RCSnippetFolderNode *sourceFolder = sourceSnippet.parentFolder;
    RCSnippetFolderNode *targetFolder = nil;

    if ([item isKindOfClass:[RCSnippetFolderNode class]]) {
        targetFolder = (RCSnippetFolderNode *)item;
    } else if ([item isKindOfClass:[RCSnippetNode class]]) {
        targetFolder = ((RCSnippetNode *)item).parentFolder;
    }

    if (targetFolder == nil || sourceFolder == nil) {
        return NO;
    }

    NSUInteger sourceIndex = [sourceFolder.snippetNodes indexOfObjectIdenticalTo:sourceSnippet];
    if (sourceIndex == NSNotFound) {
        return NO;
    }

    NSInteger targetIndex = index;
    if (targetIndex < 0 || targetIndex > (NSInteger)targetFolder.snippetNodes.count) {
        targetIndex = (NSInteger)targetFolder.snippetNodes.count;
    }

    [sourceFolder.snippetNodes removeObjectAtIndex:sourceIndex];
    if (sourceFolder == targetFolder && (NSUInteger)targetIndex > sourceIndex) {
        targetIndex--;
    }
    if (targetIndex < 0) {
        targetIndex = 0;
    }

    [targetFolder.snippetNodes insertObject:sourceSnippet atIndex:(NSUInteger)targetIndex];
    sourceSnippet.parentFolder = targetFolder;

    NSString *targetFolderIdentifier = [self stringValueFromDictionary:targetFolder.folderDictionary
                                                                   key:@"identifier"
                                                          defaultValue:@""];
    if (targetFolderIdentifier.length > 0) {
        sourceSnippet.snippetDictionary[@"folder_id"] = targetFolderIdentifier;
    }

    BOOL allUpdatesSucceeded = [self persistSnippetOrderForFolder:sourceFolder];
    if (targetFolder != sourceFolder) {
        allUpdatesSucceeded = allUpdatesSucceeded && [self persistSnippetOrderForFolder:targetFolder];
    }
    if (!allUpdatesSucceeded) {
        [self reloadOutlineSelectingFolderIdentifier:nil snippetIdentifier:nil];
        return NO;
    }

    [outlineView reloadData];
    [self expandAllFolders];
    [self selectItem:sourceSnippet];
    [[RCMenuManager shared] rebuildMenu];
    return YES;
}

#pragma mark - OutlineView Delegate

- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item {
    if ([item isKindOfClass:[RCSnippetFolderNode class]]) {
        NSInteger row = [outlineView rowForItem:item];
        if (row > 0) {
            return 30.0;
        }
    }
    return 22.0;
}

- (nullable NSView *)outlineView:(NSOutlineView *)outlineView
              viewForTableColumn:(NSTableColumn *)tableColumn
                            item:(id)item {
    (void)tableColumn;

    BOOL isFolder = [item isKindOfClass:[RCSnippetFolderNode class]];
    NSInteger row = [outlineView rowForItem:item];
    BOOL useSpacedFolderCell = isFolder && row > 0;

    NSString *cellIdentifier = useSpacedFolderCell ? @"RCSnippetEditorFolderSpacedCell" : @"RCSnippetEditorCell";
    NSTableCellView *cell = [outlineView makeViewWithIdentifier:cellIdentifier owner:self];
    if (cell == nil) {
        CGFloat defaultHeight = useSpacedFolderCell ? 30.0 : 22.0;
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, defaultHeight)];
        cell.identifier = cellIdentifier;

        NSTextField *textField = [NSTextField labelWithString:@""];
        textField.translatesAutoresizingMaskIntoConstraints = NO;
        textField.lineBreakMode = NSLineBreakByTruncatingTail;

        [cell addSubview:textField];
        cell.textField = textField;

        NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
            [textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2.0],
            [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4.0],
        ]];
        if (useSpacedFolderCell) {
            [constraints addObject:[textField.bottomAnchor constraintEqualToAnchor:cell.bottomAnchor constant:-4.0]];
        } else {
            [constraints addObject:[textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]];
        }
        [NSLayoutConstraint activateConstraints:constraints];
    }

    if (isFolder) {
        RCSnippetFolderNode *folderNode = (RCSnippetFolderNode *)item;
        NSString *title = [self stringValueFromDictionary:folderNode.folderDictionary
                                                       key:@"title"
                                              defaultValue:@""];
        cell.textField.stringValue = (title.length > 0) ? title : NSLocalizedString(@"Untitled Folder", nil);
    } else {
        RCSnippetNode *snippetNode = (RCSnippetNode *)item;
        NSString *title = [self stringValueFromDictionary:snippetNode.snippetDictionary
                                                       key:@"title"
                                              defaultValue:@""];
        if (title.length == 0) {
            NSString *content = [self stringValueFromDictionary:snippetNode.snippetDictionary
                                                            key:@"content"
                                                   defaultValue:@""];
            title = (content.length > 0) ? [self truncatedString:content maxLength:24] : NSLocalizedString(@"Untitled Snippet", nil);
        }
        cell.textField.stringValue = title;
    }

    if ([self isItemEnabled:item]) {
        cell.textField.textColor = NSColor.labelColor;
    } else {
        cell.textField.textColor = NSColor.secondaryLabelColor;
    }

    return cell;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    (void)notification;
    [self refreshEditorForSelection];
}

#pragma mark - Persist Order

- (BOOL)persistFolderOrderFromCurrentTree {
    RCDatabaseManager *databaseManager = [RCDatabaseManager shared];
    __block BOOL allUpdatesSucceeded = YES;

    [self.folderNodes enumerateObjectsUsingBlock:^(RCSnippetFolderNode * _Nonnull folderNode, NSUInteger index, BOOL * _Nonnull stop) {
        folderNode.folderDictionary[@"folder_index"] = @((NSInteger)index);
        if (![databaseManager updateSnippetFolder:folderNode.folderDictionary]) {
            allUpdatesSucceeded = NO;
            *stop = YES;
        }
    }];

    return allUpdatesSucceeded;
}

- (BOOL)persistSnippetOrderForFolder:(RCSnippetFolderNode *)folderNode {
    if (folderNode == nil) {
        return NO;
    }

    NSString *folderIdentifier = [self stringValueFromDictionary:folderNode.folderDictionary
                                                             key:@"identifier"
                                                    defaultValue:@""];
    if (folderIdentifier.length == 0) {
        return NO;
    }

    RCDatabaseManager *databaseManager = [RCDatabaseManager shared];
    __block BOOL allUpdatesSucceeded = YES;
    [folderNode.snippetNodes enumerateObjectsUsingBlock:^(RCSnippetNode * _Nonnull snippetNode, NSUInteger index, BOOL * _Nonnull stop) {
        snippetNode.snippetDictionary[@"folder_id"] = folderIdentifier;
        snippetNode.snippetDictionary[@"snippet_index"] = @((NSInteger)index);
        if (![databaseManager updateSnippet:snippetNode.snippetDictionary]) {
            allUpdatesSucceeded = NO;
            *stop = YES;
        }
    }];

    return allUpdatesSucceeded;
}

#pragma mark - Helpers

- (void)flashSaveSuccess {
    NSString *originalTitle = self.saveButton.title;
    self.saveButton.title = NSLocalizedString(@"Saved!", nil);
    self.saveButton.enabled = NO;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        strongSelf.saveButton.title = originalTitle;
        strongSelf.saveButton.enabled = ([strongSelf selectedItem] != nil);
    });
}

- (NSURL *)defaultClipySnippetsFileURL {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/com.clipy-app.Clipy/snippets.xml"];
    return [NSURL fileURLWithPath:path];
}

- (NSURL *)chooseImportFileURLWithDefaultDirectoryURL:(NSURL *)directoryURL {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.allowedContentTypes = @[
        RCSnippetImportExportContentType(),
        UTTypeXML,
        UTTypePropertyList,
    ];
    if (directoryURL != nil) {
        panel.directoryURL = directoryURL;
    }

    NSModalResponse response = [panel runModal];
    if (response != NSModalResponseOK) {
        return nil;
    }
    return panel.URL;
}

- (void)presentSnippetImportExportError:(NSError *)error title:(NSString *)title {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleCritical;
    alert.messageText = title ?: NSLocalizedString(@"An unknown error occurred.", nil);
    alert.informativeText = error.localizedDescription ?: NSLocalizedString(@"An unknown error occurred.", nil);
    [alert addButtonWithTitle:NSLocalizedString(@"OK", nil)];
    [alert runModal];
}

- (NSArray<NSDictionary *> *)folderDictionariesForExportItem:(id)item {
    if ([item isKindOfClass:[RCSnippetFolderNode class]]) {
        RCSnippetFolderNode *folderNode = (RCSnippetFolderNode *)item;
        NSDictionary *folderDictionary = [self exportFolderDictionaryFromFolderNode:folderNode
                                                                        snippetNodes:folderNode.snippetNodes];
        return (folderDictionary != nil) ? @[folderDictionary] : @[];
    }

    if ([item isKindOfClass:[RCSnippetNode class]]) {
        RCSnippetNode *snippetNode = (RCSnippetNode *)item;
        RCSnippetFolderNode *folderNode = snippetNode.parentFolder;
        if (folderNode == nil) {
            return @[];
        }

        NSDictionary *folderDictionary = [self exportFolderDictionaryFromFolderNode:folderNode
                                                                        snippetNodes:@[snippetNode]];
        return (folderDictionary != nil) ? @[folderDictionary] : @[];
    }

    return @[];
}

- (NSDictionary *)exportFolderDictionaryFromFolderNode:(RCSnippetFolderNode *)folderNode
                                           snippetNodes:(NSArray<RCSnippetNode *> *)snippetNodes {
    if (folderNode == nil) {
        return nil;
    }

    NSString *folderIdentifier = [self stringValueFromDictionary:folderNode.folderDictionary
                                                              key:@"identifier"
                                                     defaultValue:NSUUID.UUID.UUIDString];
    NSString *folderTitle = [self stringValueFromDictionary:folderNode.folderDictionary
                                                        key:@"title"
                                               defaultValue:NSLocalizedString(@"Untitled Folder", nil)];
    BOOL folderEnabled = [self boolValueFromDictionary:folderNode.folderDictionary key:@"enabled" defaultValue:YES];
    NSInteger folderIndex = [self integerValueFromDictionary:folderNode.folderDictionary key:@"folder_index" defaultValue:0];

    NSMutableArray<NSDictionary *> *snippets = [NSMutableArray arrayWithCapacity:snippetNodes.count];
    [snippetNodes enumerateObjectsUsingBlock:^(RCSnippetNode * _Nonnull snippetNode, NSUInteger index, BOOL * _Nonnull stop) {
        (void)stop;

        NSString *snippetIdentifier = [self stringValueFromDictionary:snippetNode.snippetDictionary
                                                                  key:@"identifier"
                                                         defaultValue:NSUUID.UUID.UUIDString];
        NSString *snippetTitle = [self stringValueFromDictionary:snippetNode.snippetDictionary
                                                             key:@"title"
                                                    defaultValue:NSLocalizedString(@"Untitled Snippet", nil)];
        NSString *snippetContent = [self stringValueFromDictionary:snippetNode.snippetDictionary
                                                               key:@"content"
                                                      defaultValue:@""];
        BOOL snippetEnabled = [self boolValueFromDictionary:snippetNode.snippetDictionary key:@"enabled" defaultValue:YES];

        [snippets addObject:@{
            @"identifier": snippetIdentifier,
            @"snippet_index": @((NSInteger)index),
            @"enabled": @(snippetEnabled),
            @"title": snippetTitle,
            @"content": snippetContent,
        }];
    }];

    return @{
        @"identifier": folderIdentifier,
        @"folder_index": @(folderIndex),
        @"enabled": @(folderEnabled),
        @"title": folderTitle,
        @"snippets": [snippets copy],
    };
}

- (NSString *)exportBaseFileNameForItem:(id)item {
    if ([item isKindOfClass:[RCSnippetFolderNode class]]) {
        RCSnippetFolderNode *folderNode = (RCSnippetFolderNode *)item;
        return [self stringValueFromDictionary:folderNode.folderDictionary key:@"title" defaultValue:@"folder"];
    }

    if ([item isKindOfClass:[RCSnippetNode class]]) {
        RCSnippetNode *snippetNode = (RCSnippetNode *)item;
        return [self stringValueFromDictionary:snippetNode.snippetDictionary key:@"title" defaultValue:@"snippet"];
    }

    return @"snippets";
}

- (NSString *)sanitizedFileNameComponent:(NSString *)name {
    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return @"snippets";
    }

    NSMutableCharacterSet *invalidSet = [NSCharacterSet characterSetWithCharactersInString:@"/\\:"].mutableCopy;
    [invalidSet formUnionWithCharacterSet:[NSCharacterSet newlineCharacterSet]];

    NSArray<NSString *> *components = [trimmed componentsSeparatedByCharactersInSet:invalidSet];
    NSString *joined = [[components filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@"_"];
    return (joined.length > 0) ? joined : @"snippets";
}

- (nullable RCSnippetFolderNode *)folderNodeForIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return nil;
    }

    for (RCSnippetFolderNode *folderNode in self.folderNodes) {
        NSString *candidate = [self stringValueFromDictionary:folderNode.folderDictionary
                                                          key:@"identifier"
                                                 defaultValue:@""];
        if ([candidate isEqualToString:identifier]) {
            return folderNode;
        }
    }
    return nil;
}

- (nullable RCSnippetNode *)snippetNodeForIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return nil;
    }

    for (RCSnippetFolderNode *folderNode in self.folderNodes) {
        for (RCSnippetNode *snippetNode in folderNode.snippetNodes) {
            NSString *candidate = [self stringValueFromDictionary:snippetNode.snippetDictionary
                                                              key:@"identifier"
                                                     defaultValue:@""];
            if ([candidate isEqualToString:identifier]) {
                return snippetNode;
            }
        }
    }

    return nil;
}

- (NSDictionary *)dragPayloadForItem:(id)item {
    if ([item isKindOfClass:[RCSnippetFolderNode class]]) {
        RCSnippetFolderNode *folderNode = (RCSnippetFolderNode *)item;
        NSString *identifier = [self stringValueFromDictionary:folderNode.folderDictionary
                                                           key:@"identifier"
                                                  defaultValue:@""];
        if (identifier.length == 0) {
            return nil;
        }

        return @{
            @"type": kRCSnippetDragTypeFolder,
            @"identifier": identifier,
        };
    }

    if ([item isKindOfClass:[RCSnippetNode class]]) {
        RCSnippetNode *snippetNode = (RCSnippetNode *)item;
        NSString *identifier = [self stringValueFromDictionary:snippetNode.snippetDictionary
                                                           key:@"identifier"
                                                  defaultValue:@""];
        if (identifier.length == 0) {
            return nil;
        }

        return @{
            @"type": kRCSnippetDragTypeSnippet,
            @"identifier": identifier,
        };
    }

    return nil;
}

- (NSDictionary *)dragPayloadFromDraggingInfo:(id<NSDraggingInfo>)draggingInfo {
    NSPasteboard *pasteboard = draggingInfo.draggingPasteboard;
    id payload = [pasteboard propertyListForType:kRCSnippetOutlineDragType];
    if (![payload isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    return (NSDictionary *)payload;
}

- (NSInteger)nextFolderIndexValue {
    NSInteger maxIndex = -1;
    for (RCSnippetFolderNode *folderNode in self.folderNodes) {
        NSInteger value = [self integerValueFromDictionary:folderNode.folderDictionary key:@"folder_index" defaultValue:0];
        if (value > maxIndex) {
            maxIndex = value;
        }
    }
    return maxIndex + 1;
}

- (NSInteger)nextSnippetIndexValueInFolder:(RCSnippetFolderNode *)folderNode {
    if (folderNode == nil) {
        return 0;
    }

    NSInteger maxIndex = -1;
    for (RCSnippetNode *node in folderNode.snippetNodes) {
        NSInteger value = [self integerValueFromDictionary:node.snippetDictionary key:@"snippet_index" defaultValue:0];
        if (value > maxIndex) {
            maxIndex = value;
        }
    }
    return maxIndex + 1;
}

- (void)updateEnabledToggleButtonForItem:(nullable id)item {
    if (self.enabledToggleButton == nil) {
        return;
    }

    if (item == nil) {
        self.enabledToggleButton.image = [NSImage imageWithSystemSymbolName:@"eye" accessibilityDescription:NSLocalizedString(@"Enable/Disable", nil)];
        return;
    }

    BOOL enabled = [self isItemEnabled:item];
    NSString *symbolName = enabled ? @"eye" : @"eye.slash";
    self.enabledToggleButton.image = [NSImage imageWithSystemSymbolName:symbolName
                                                   accessibilityDescription:NSLocalizedString(@"Enable/Disable", nil)];
}

- (BOOL)isItemEnabled:(id)item {
    if ([item isKindOfClass:[RCSnippetFolderNode class]]) {
        RCSnippetFolderNode *folderNode = (RCSnippetFolderNode *)item;
        return [self boolValueFromDictionary:folderNode.folderDictionary key:@"enabled" defaultValue:YES];
    }

    if ([item isKindOfClass:[RCSnippetNode class]]) {
        RCSnippetNode *snippetNode = (RCSnippetNode *)item;
        return [self boolValueFromDictionary:snippetNode.snippetDictionary key:@"enabled" defaultValue:YES];
    }

    return YES;
}

- (NSString *)normalizedTitleFromField:(NSTextField *)field fallback:(NSString *)fallback {
    NSString *title = [field.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (title.length == 0) {
        return fallback ?: @"";
    }
    return title;
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

- (NSInteger)integerValueFromDictionary:(NSDictionary *)dictionary key:(NSString *)key defaultValue:(NSInteger)defaultValue {
    id rawValue = dictionary[key];
    if ([rawValue isKindOfClass:[NSNumber class]]) {
        return [rawValue integerValue];
    }
    if ([rawValue isKindOfClass:[NSString class]]) {
        return [(NSString *)rawValue integerValue];
    }
    return defaultValue;
}

- (BOOL)boolValueFromDictionary:(NSDictionary *)dictionary key:(NSString *)key defaultValue:(BOOL)defaultValue {
    id rawValue = dictionary[key];
    if ([rawValue isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)rawValue boolValue];
    }
    if ([rawValue isKindOfClass:[NSString class]]) {
        NSString *normalized = [[(NSString *)rawValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
        if ([normalized isEqualToString:@"1"]
            || [normalized isEqualToString:@"true"]
            || [normalized isEqualToString:@"yes"]) {
            return YES;
        }
        if ([normalized isEqualToString:@"0"]
            || [normalized isEqualToString:@"false"]
            || [normalized isEqualToString:@"no"]) {
            return NO;
        }
    }
    return defaultValue;
}

@end

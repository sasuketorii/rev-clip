//
//  RCPreferencesWindowController.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCPreferencesWindowController.h"

#import "RCBetaPreferencesViewController.h"
#import "RCExcludePreferencesViewController.h"
#import "RCGeneralPreferencesViewController.h"
#import "RCMenuPreferencesViewController.h"
#import "RCShortcutsPreferencesViewController.h"
#import "RCTypePreferencesViewController.h"
#import "RCUpdatesPreferencesViewController.h"

NSString * const RCPreferencesTabGeneral = @"general";
NSString * const RCPreferencesTabMenu = @"menu";
NSString * const RCPreferencesTabType = @"type";
NSString * const RCPreferencesTabExclude = @"exclude";
NSString * const RCPreferencesTabShortcuts = @"shortcuts";
NSString * const RCPreferencesTabUpdates = @"updates";
NSString * const RCPreferencesTabBeta = @"beta";

@interface RCPreferencesWindowController () <NSToolbarDelegate>

@property (nonatomic, strong, nullable) RCGeneralPreferencesViewController *generalViewController;
@property (nonatomic, strong, nullable) RCMenuPreferencesViewController *menuViewController;
@property (nonatomic, strong, nullable) RCTypePreferencesViewController *typeViewController;
@property (nonatomic, strong, nullable) RCExcludePreferencesViewController *excludeViewController;
@property (nonatomic, strong, nullable) RCShortcutsPreferencesViewController *shortcutsViewController;
@property (nonatomic, strong, nullable) RCUpdatesPreferencesViewController *updatesViewController;
@property (nonatomic, strong, nullable) RCBetaPreferencesViewController *betaViewController;
@property (nonatomic, assign) BOOL centeredOnFirstShow;

@end

@implementation RCPreferencesWindowController

+ (instancetype)shared {
    static RCPreferencesWindowController *sharedController = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedController = [[self alloc] init];
    });
    return sharedController;
}

- (instancetype)init {
    self = [super initWithWindowNibName:@"RCPreferencesWindow"];
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];

    [self configureWindow];
    [self configureToolbar];
    [self showTab:RCPreferencesTabGeneral];
}

- (void)showWindow:(id)sender {
    if (!self.centeredOnFirstShow) {
        [self.window center];
        self.centeredOnFirstShow = YES;
    }

    [super showWindow:sender];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:sender];
}

- (void)showTab:(NSString *)tabIdentifier {
    NSString *resolvedTabIdentifier = tabIdentifier.length > 0 ? tabIdentifier : RCPreferencesTabGeneral;
    NSViewController *viewController = [self viewControllerForTabIdentifier:resolvedTabIdentifier];
    if (viewController == nil) {
        resolvedTabIdentifier = RCPreferencesTabGeneral;
        viewController = [self viewControllerForTabIdentifier:resolvedTabIdentifier];
    }
    if (viewController == nil) {
        return;
    }

    [self switchToViewController:viewController];
    self.window.toolbar.selectedItemIdentifier = resolvedTabIdentifier;
}

#pragma mark - Toolbar

- (void)configureToolbar {
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"RCPreferencesToolbar"];
    toolbar.delegate = self;
    toolbar.allowsUserCustomization = NO;
    toolbar.autosavesConfiguration = NO;
    toolbar.displayMode = NSToolbarDisplayModeIconAndLabel;

    self.window.toolbar = toolbar;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    (void)toolbar;
    return [self tabIdentifiers];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    (void)toolbar;
    return [self tabIdentifiers];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar {
    (void)toolbar;
    return [self tabIdentifiers];
}

- (nullable NSToolbarItem *)toolbar:(NSToolbar *)toolbar
              itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
          willBeInsertedIntoToolbar:(BOOL)willBeInserted {
    (void)toolbar;
    (void)willBeInserted;

    NSString *title = [self titleForTabIdentifier:itemIdentifier];
    if (title.length == 0) {
        return nil;
    }

    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
    item.label = title;
    item.paletteLabel = title;
    item.toolTip = title;
    item.target = self;
    item.action = @selector(toolbarItemSelected:);

    NSString *symbolName = [self symbolNameForTabIdentifier:itemIdentifier];
    if (symbolName.length > 0) {
        item.image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:title];
    }

    return item;
}

- (void)toolbarItemSelected:(NSToolbarItem *)sender {
    [self showTab:sender.itemIdentifier];
}

#pragma mark - View Controller Switch

- (void)switchToViewController:(NSViewController *)viewController {
    NSView *newView = viewController.view;
    NSSize newSize = newView.fittingSize;
    if (newSize.width < 1.0 || newSize.height < 1.0) {
        newSize = newView.frame.size;
    }

    NSRect windowFrame = self.window.frame;
    CGFloat titleBarHeight = windowFrame.size.height - self.window.contentLayoutRect.size.height;
    NSRect newFrame = NSMakeRect(
        windowFrame.origin.x,
        windowFrame.origin.y + windowFrame.size.height - newSize.height - titleBarHeight,
        newSize.width,
        newSize.height + titleBarHeight
    );

    [self.window setFrame:newFrame display:YES animate:YES];
    self.window.contentView = newView;
}

#pragma mark - Private

- (void)configureWindow {
    NSWindow *window = self.window;
    window.title = NSLocalizedString(@"Preferences", nil);
    window.styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
    window.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace;
    window.releasedWhenClosed = NO;
}

- (NSArray<NSString *> *)tabIdentifiers {
    return @[
        RCPreferencesTabGeneral,
        RCPreferencesTabMenu,
        RCPreferencesTabType,
        RCPreferencesTabExclude,
        RCPreferencesTabShortcuts,
        RCPreferencesTabUpdates,
        RCPreferencesTabBeta,
    ];
}

- (nullable NSViewController *)viewControllerForTabIdentifier:(NSString *)tabIdentifier {
    if ([tabIdentifier isEqualToString:RCPreferencesTabGeneral]) {
        if (self.generalViewController == nil) {
            self.generalViewController = [[RCGeneralPreferencesViewController alloc] initWithNibName:@"RCGeneralPreferencesView" bundle:nil];
        }
        return self.generalViewController;
    }

    if ([tabIdentifier isEqualToString:RCPreferencesTabMenu]) {
        if (self.menuViewController == nil) {
            self.menuViewController = [[RCMenuPreferencesViewController alloc] initWithNibName:@"RCMenuPreferencesView" bundle:nil];
        }
        return self.menuViewController;
    }

    if ([tabIdentifier isEqualToString:RCPreferencesTabType]) {
        if (self.typeViewController == nil) {
            self.typeViewController = [[RCTypePreferencesViewController alloc] initWithNibName:@"RCTypePreferencesView" bundle:nil];
        }
        return self.typeViewController;
    }

    if ([tabIdentifier isEqualToString:RCPreferencesTabExclude]) {
        if (self.excludeViewController == nil) {
            self.excludeViewController = [[RCExcludePreferencesViewController alloc] initWithNibName:@"RCExcludePreferencesView" bundle:nil];
        }
        return self.excludeViewController;
    }

    if ([tabIdentifier isEqualToString:RCPreferencesTabShortcuts]) {
        if (self.shortcutsViewController == nil) {
            self.shortcutsViewController = [[RCShortcutsPreferencesViewController alloc] initWithNibName:@"RCShortcutsPreferencesView" bundle:nil];
        }
        return self.shortcutsViewController;
    }

    if ([tabIdentifier isEqualToString:RCPreferencesTabUpdates]) {
        if (self.updatesViewController == nil) {
            self.updatesViewController = [[RCUpdatesPreferencesViewController alloc] initWithNibName:@"RCUpdatesPreferencesView" bundle:nil];
        }
        return self.updatesViewController;
    }

    if ([tabIdentifier isEqualToString:RCPreferencesTabBeta]) {
        if (self.betaViewController == nil) {
            self.betaViewController = [[RCBetaPreferencesViewController alloc] initWithNibName:@"RCBetaPreferencesView" bundle:nil];
        }
        return self.betaViewController;
    }

    return nil;
}

- (NSString *)titleForTabIdentifier:(NSString *)tabIdentifier {
    if ([tabIdentifier isEqualToString:RCPreferencesTabGeneral]) {
        return NSLocalizedString(@"General", nil);
    }
    if ([tabIdentifier isEqualToString:RCPreferencesTabMenu]) {
        return NSLocalizedString(@"Menu", nil);
    }
    if ([tabIdentifier isEqualToString:RCPreferencesTabType]) {
        return NSLocalizedString(@"Type", nil);
    }
    if ([tabIdentifier isEqualToString:RCPreferencesTabExclude]) {
        return NSLocalizedString(@"Excluded Apps", nil);
    }
    if ([tabIdentifier isEqualToString:RCPreferencesTabShortcuts]) {
        return NSLocalizedString(@"Shortcuts", nil);
    }
    if ([tabIdentifier isEqualToString:RCPreferencesTabUpdates]) {
        return NSLocalizedString(@"Updates", nil);
    }
    if ([tabIdentifier isEqualToString:RCPreferencesTabBeta]) {
        return NSLocalizedString(@"Beta", nil);
    }
    return @"";
}

- (NSString *)symbolNameForTabIdentifier:(NSString *)tabIdentifier {
    if ([tabIdentifier isEqualToString:RCPreferencesTabGeneral]) {
        return @"gearshape";
    }
    if ([tabIdentifier isEqualToString:RCPreferencesTabMenu]) {
        return @"list.bullet";
    }
    if ([tabIdentifier isEqualToString:RCPreferencesTabType]) {
        return @"doc.on.doc";
    }
    if ([tabIdentifier isEqualToString:RCPreferencesTabExclude]) {
        return @"xmark.app";
    }
    if ([tabIdentifier isEqualToString:RCPreferencesTabShortcuts]) {
        return @"keyboard";
    }
    if ([tabIdentifier isEqualToString:RCPreferencesTabUpdates]) {
        return @"arrow.triangle.2.circlepath";
    }
    if ([tabIdentifier isEqualToString:RCPreferencesTabBeta]) {
        return @"flask";
    }
    return @"";
}

@end

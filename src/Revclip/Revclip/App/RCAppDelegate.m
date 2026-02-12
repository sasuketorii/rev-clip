//
//  RCAppDelegate.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCAppDelegate.h"

#import "RCAccessibilityService.h"
#import "RCClipboardService.h"
#import "RCEnvironment.h"
#import "RCDatabaseManager.h"
#import "RCMenuManager.h"
#import "RCPasteService.h"
#import "RCUtilities.h"

@implementation RCAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [RCUtilities registerDefaultSettings];

    RCDatabaseManager *databaseManager = [RCDatabaseManager shared];
    [databaseManager setupDatabase];

    RCClipboardService *clipboardService = [RCClipboardService shared];
    RCMenuManager *menuManager = [RCMenuManager shared];
    RCPasteService *pasteService = [RCPasteService shared];
    RCAccessibilityService *accessibilityService = [RCAccessibilityService shared];

    RCEnvironment *environment = [RCEnvironment shared];
    environment.databaseManager = databaseManager;
    environment.clipboardService = clipboardService;
    environment.menuManager = menuManager;
    environment.pasteService = pasteService;
    environment.accessibilityService = accessibilityService;

    [menuManager setupStatusItem];
    [clipboardService startMonitoring];
    [clipboardService captureCurrentClipboard];

    [[RCAccessibilityService shared] checkAndRequestAccessibilityWithAlert];
    NSLog(@"[Revclip] Application did finish launching.");
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [[RCClipboardService shared] stopMonitoring];
}

@end

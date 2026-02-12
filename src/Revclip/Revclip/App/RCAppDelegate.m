//
//  RCAppDelegate.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCAppDelegate.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "RCAccessibilityService.h"
#import "RCClipboardService.h"
#import "RCDataCleanService.h"
#import "RCEnvironment.h"
#import "RCDatabaseManager.h"
#import "RCHotKeyService.h"
#import "RCMenuManager.h"
#import "RCPreferencesWindowController.h"
#import "RCPasteService.h"
#import "RCSnippetEditorWindowController.h"
#import "RCSnippetImportExportService.h"
#import "RCUtilities.h"

@interface RCAppDelegate ()

- (void)presentSnippetImportExportError:(NSError *)error title:(NSString *)title;
- (BOOL)promptMergeOptionReturningMerge:(BOOL *)merge;

@end

@implementation RCAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [RCUtilities registerDefaultSettings];

    RCDatabaseManager *databaseManager = [RCDatabaseManager shared];
    [databaseManager setupDatabase];

    RCClipboardService *clipboardService = [RCClipboardService shared];
    RCMenuManager *menuManager = [RCMenuManager shared];
    RCPasteService *pasteService = [RCPasteService shared];
    RCHotKeyService *hotKeyService = [RCHotKeyService shared];
    RCAccessibilityService *accessibilityService = [RCAccessibilityService shared];
    RCDataCleanService *dataCleanService = [RCDataCleanService shared];

    RCEnvironment *environment = [RCEnvironment shared];
    environment.databaseManager = databaseManager;
    environment.clipboardService = clipboardService;
    environment.menuManager = menuManager;
    environment.pasteService = pasteService;
    environment.hotKeyService = hotKeyService;
    environment.accessibilityService = accessibilityService;
    environment.dataCleanService = dataCleanService;

    [menuManager setupStatusItem];
    [hotKeyService loadAndRegisterHotKeysFromDefaults];
    [dataCleanService startCleanupTimer];
    [clipboardService startMonitoring];
    [clipboardService captureCurrentClipboard];

    [[RCAccessibilityService shared] checkAndRequestAccessibilityWithAlert];
    NSLog(@"[Revclip] Application did finish launching.");
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [[RCDataCleanService shared] stopCleanupTimer];
    [[RCClipboardService shared] stopMonitoring];
    [[RCHotKeyService shared] unregisterAllHotKeys];
}

- (IBAction)showPreferencesWindow:(id)sender {
    [[RCPreferencesWindowController shared] showWindow:sender];
}

- (IBAction)showPreferences:(id)sender {
    [self showPreferencesWindow:sender];
}

- (IBAction)showSnippetEditor:(id)sender {
    [[RCSnippetEditorWindowController shared] showWindow:sender];
}

- (IBAction)importSnippets:(id)sender {
    (void)sender;

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.allowedContentTypes = @[UTTypeXML];

    NSModalResponse openResponse = [panel runModal];
    if (openResponse != NSModalResponseOK || panel.URL == nil) {
        return;
    }

    BOOL merge = YES;
    if (![self promptMergeOptionReturningMerge:&merge]) {
        return;
    }

    NSError *importError = nil;
    BOOL imported = [[RCSnippetImportExportService shared] importSnippetsFromURL:panel.URL
                                                                            merge:merge
                                                                            error:&importError];
    if (!imported) {
        [self presentSnippetImportExportError:importError title:@"Failed to Import Snippets"];
        return;
    }

    [[RCHotKeyService shared] reloadFolderHotKeys];
    [[RCMenuManager shared] rebuildMenu];
}

- (IBAction)exportSnippets:(id)sender {
    (void)sender;

    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.canCreateDirectories = YES;
    panel.nameFieldStringValue = @"snippets.xml";
    panel.allowedContentTypes = @[UTTypeXML];

    NSModalResponse saveResponse = [panel runModal];
    if (saveResponse != NSModalResponseOK || panel.URL == nil) {
        return;
    }

    NSError *exportError = nil;
    BOOL exported = [[RCSnippetImportExportService shared] exportSnippetsToURL:panel.URL error:&exportError];
    if (!exported) {
        [self presentSnippetImportExportError:exportError title:@"Failed to Export Snippets"];
    }
}

#pragma mark - Private

- (void)presentSnippetImportExportError:(NSError *)error title:(NSString *)title {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleCritical;
    alert.messageText = title;
    alert.informativeText = error.localizedDescription ?: @"An unknown error occurred.";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (BOOL)promptMergeOptionReturningMerge:(BOOL *)merge {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = @"How do you want to import snippets?";
    alert.informativeText = @"Choose whether to merge with existing snippets or replace them all.";
    [alert addButtonWithTitle:@"Merge with existing snippets"];
    [alert addButtonWithTitle:@"Replace all snippets"];
    [alert addButtonWithTitle:@"Cancel"];

    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        if (merge != NULL) {
            *merge = YES;
        }
        return YES;
    }
    if (response == NSAlertSecondButtonReturn) {
        if (merge != NULL) {
            *merge = NO;
        }
        return YES;
    }
    return NO;
}

@end

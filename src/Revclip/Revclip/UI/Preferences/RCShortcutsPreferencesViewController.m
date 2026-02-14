//
//  RCShortcutsPreferencesViewController.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCShortcutsPreferencesViewController.h"

#import "RCConstants.h"
#import "RCHotKeyRecorderView.h"
#import "RCHotKeyService.h"

static UInt32 const kRCDefaultKeyCodeV = 9;
static UInt32 const kRCDefaultKeyCodeB = 11;

@interface RCShortcutsPreferencesViewController () <RCHotKeyRecorderViewDelegate>

@property (nonatomic, weak) IBOutlet RCHotKeyRecorderView *mainMenuRecorderView;
@property (nonatomic, weak) IBOutlet RCHotKeyRecorderView *historyMenuRecorderView;
@property (nonatomic, weak) IBOutlet RCHotKeyRecorderView *snippetMenuRecorderView;
@property (nonatomic, weak) IBOutlet RCHotKeyRecorderView *clearHistoryRecorderView;

- (void)reloadRecordersFromDefaults;
- (nullable NSString *)userDefaultsKeyForRecorderView:(RCHotKeyRecorderView *)recorderView;
- (RCKeyCombo)keyComboForDefaultsKey:(NSString *)defaultsKey;
- (RCKeyCombo)defaultKeyComboForDefaultsKey:(NSString *)defaultsKey;
- (void)reloadHotKeysAndRecorders;
- (void)resetHotKeysToDefaults;

@end

@implementation RCShortcutsPreferencesViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.mainMenuRecorderView.delegate = self;
    self.historyMenuRecorderView.delegate = self;
    self.snippetMenuRecorderView.delegate = self;
    self.clearHistoryRecorderView.delegate = self;

    [self reloadRecordersFromDefaults];
}

#pragma mark - Actions

- (IBAction)resetToDefaults:(id)sender {
    (void)sender;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = NSLocalizedString(@"Reset all shortcuts to defaults?", nil);
    alert.informativeText = NSLocalizedString(@"Main Menu, History Menu, and Snippet Menu will be restored. Clear History will be removed.", nil);
    [alert addButtonWithTitle:NSLocalizedString(@"Reset", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];

    NSWindow *window = self.view.window;
    if (window != nil) {
        __weak typeof(self) weakSelf = self;
        [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
            typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            if (returnCode == NSAlertFirstButtonReturn) {
                [strongSelf resetHotKeysToDefaults];
            }
        }];
        return;
    }

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [self resetHotKeysToDefaults];
    }
}

#pragma mark - RCHotKeyRecorderViewDelegate

- (void)hotKeyRecorderView:(RCHotKeyRecorderView *)recorderView didRecordKeyCombo:(RCKeyCombo)keyCombo {
    NSString *defaultsKey = [self userDefaultsKeyForRecorderView:recorderView];
    if (defaultsKey.length == 0) {
        return;
    }

    [RCHotKeyService saveKeyCombo:keyCombo toUserDefaults:defaultsKey];
    [self reloadHotKeysAndRecorders];
}

- (void)hotKeyRecorderViewDidClearKeyCombo:(RCHotKeyRecorderView *)recorderView {
    NSString *defaultsKey = [self userDefaultsKeyForRecorderView:recorderView];
    if (defaultsKey.length == 0) {
        return;
    }

    [[NSUserDefaults standardUserDefaults] removeObjectForKey:defaultsKey];
    [self reloadHotKeysAndRecorders];
}

#pragma mark - Private

- (void)reloadRecordersFromDefaults {
    self.mainMenuRecorderView.keyCombo = [self keyComboForDefaultsKey:kRCHotKeyMainKeyCombo];
    self.historyMenuRecorderView.keyCombo = [self keyComboForDefaultsKey:kRCHotKeyHistoryKeyCombo];
    self.snippetMenuRecorderView.keyCombo = [self keyComboForDefaultsKey:kRCHotKeySnippetKeyCombo];
    self.clearHistoryRecorderView.keyCombo = [self keyComboForDefaultsKey:kRCClearHistoryKeyCombo];
}

- (nullable NSString *)userDefaultsKeyForRecorderView:(RCHotKeyRecorderView *)recorderView {
    if (recorderView == self.mainMenuRecorderView) {
        return kRCHotKeyMainKeyCombo;
    }
    if (recorderView == self.historyMenuRecorderView) {
        return kRCHotKeyHistoryKeyCombo;
    }
    if (recorderView == self.snippetMenuRecorderView) {
        return kRCHotKeySnippetKeyCombo;
    }
    if (recorderView == self.clearHistoryRecorderView) {
        return kRCClearHistoryKeyCombo;
    }
    return nil;
}

- (RCKeyCombo)keyComboForDefaultsKey:(NSString *)defaultsKey {
    RCKeyCombo combo = [RCHotKeyService keyComboFromUserDefaults:defaultsKey];
    if (RCIsValidKeyCombo(combo)) {
        return combo;
    }
    return [self defaultKeyComboForDefaultsKey:defaultsKey];
}

- (RCKeyCombo)defaultKeyComboForDefaultsKey:(NSString *)defaultsKey {
    if ([defaultsKey isEqualToString:kRCHotKeyMainKeyCombo]) {
        return RCMakeKeyCombo(kRCDefaultKeyCodeV, controlKey | shiftKey);
    }
    if ([defaultsKey isEqualToString:kRCHotKeyHistoryKeyCombo]) {
        return RCMakeKeyCombo(kRCDefaultKeyCodeV, cmdKey | controlKey);
    }
    if ([defaultsKey isEqualToString:kRCHotKeySnippetKeyCombo]) {
        return RCMakeKeyCombo(kRCDefaultKeyCodeB, cmdKey | shiftKey);
    }
    return RCInvalidKeyCombo();
}

- (void)reloadHotKeysAndRecorders {
    [[RCHotKeyService shared] loadAndRegisterHotKeysFromDefaults];
    [self reloadRecordersFromDefaults];
}

- (void)resetHotKeysToDefaults {
    [RCHotKeyService saveKeyCombo:[self defaultKeyComboForDefaultsKey:kRCHotKeyMainKeyCombo]
                   toUserDefaults:kRCHotKeyMainKeyCombo];
    [RCHotKeyService saveKeyCombo:[self defaultKeyComboForDefaultsKey:kRCHotKeyHistoryKeyCombo]
                   toUserDefaults:kRCHotKeyHistoryKeyCombo];
    [RCHotKeyService saveKeyCombo:[self defaultKeyComboForDefaultsKey:kRCHotKeySnippetKeyCombo]
                   toUserDefaults:kRCHotKeySnippetKeyCombo];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kRCClearHistoryKeyCombo];

    [self reloadHotKeysAndRecorders];
}

@end

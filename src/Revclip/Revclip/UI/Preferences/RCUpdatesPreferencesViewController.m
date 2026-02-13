//
//  RCUpdatesPreferencesViewController.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCUpdatesPreferencesViewController.h"

#import "RCConstants.h"
#import "RCUpdateService.h"

static const NSInteger kRCDefaultUpdateCheckInterval = 86400;

@interface RCUpdatesPreferencesViewController ()

@property (nonatomic, weak) IBOutlet NSButton *automaticCheckButton;
@property (nonatomic, weak) IBOutlet NSPopUpButton *checkIntervalPopUpButton;
@property (nonatomic, weak) IBOutlet NSTextField *versionInfoLabel;

@end

@implementation RCUpdatesPreferencesViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self loadUpdateSettings];
    [self updateVersionInfo];
}

- (void)loadUpdateSettings {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;

    NSNumber *automaticCheckValue = [defaults objectForKey:kRCEnableAutomaticCheckKey];
    BOOL automaticCheckEnabled = automaticCheckValue != nil ? automaticCheckValue.boolValue : YES;
    self.automaticCheckButton.state = automaticCheckEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    if (automaticCheckValue == nil) {
        [defaults setBool:automaticCheckEnabled forKey:kRCEnableAutomaticCheckKey];
    }

    NSNumber *checkIntervalValue = [defaults objectForKey:kRCUpdateCheckIntervalKey];
    NSInteger intervalInSeconds = checkIntervalValue != nil ? checkIntervalValue.integerValue : kRCDefaultUpdateCheckInterval;
    NSMenuItem *intervalItem = [self.checkIntervalPopUpButton.menu itemWithTag:intervalInSeconds];
    if (intervalItem == nil) {
        intervalInSeconds = kRCDefaultUpdateCheckInterval;
    }
    [self.checkIntervalPopUpButton selectItemWithTag:intervalInSeconds];
    [defaults setInteger:intervalInSeconds forKey:kRCUpdateCheckIntervalKey];

    [self updateIntervalControlState];
}

- (void)updateVersionInfo {
    NSDictionary<NSString *, id> *infoDictionary = NSBundle.mainBundle.infoDictionary;
    NSString *shortVersion = [infoDictionary[@"CFBundleShortVersionString"] isKindOfClass:NSString.class] ? infoDictionary[@"CFBundleShortVersionString"] : @"";
    NSString *buildVersion = [infoDictionary[@"CFBundleVersion"] isKindOfClass:NSString.class] ? infoDictionary[@"CFBundleVersion"] : @"";

    if (shortVersion.length > 0 && buildVersion.length > 0) {
        self.versionInfoLabel.stringValue = [NSString stringWithFormat:NSLocalizedString(@"Version %@ (%@)", nil), shortVersion, buildVersion];
        return;
    }
    if (shortVersion.length > 0) {
        self.versionInfoLabel.stringValue = [NSString stringWithFormat:NSLocalizedString(@"Version %@", nil), shortVersion];
        return;
    }
    if (buildVersion.length > 0) {
        self.versionInfoLabel.stringValue = [NSString stringWithFormat:NSLocalizedString(@"Build %@", nil), buildVersion];
        return;
    }

    self.versionInfoLabel.stringValue = NSLocalizedString(@"Version -", nil);
}

- (void)updateIntervalControlState {
    BOOL automaticCheckEnabled = self.automaticCheckButton.state == NSControlStateValueOn;
    self.checkIntervalPopUpButton.enabled = automaticCheckEnabled;
}

- (IBAction)automaticCheckToggled:(NSButton *)sender {
    BOOL automaticCheckEnabled = sender.state == NSControlStateValueOn;
    [NSUserDefaults.standardUserDefaults setBool:automaticCheckEnabled forKey:kRCEnableAutomaticCheckKey];
    [self updateIntervalControlState];
}

- (IBAction)checkIntervalChanged:(NSPopUpButton *)sender {
    NSInteger intervalInSeconds = sender.selectedTag;
    if (intervalInSeconds <= 0) {
        intervalInSeconds = kRCDefaultUpdateCheckInterval;
        [sender selectItemWithTag:intervalInSeconds];
    }

    [NSUserDefaults.standardUserDefaults setInteger:intervalInSeconds forKey:kRCUpdateCheckIntervalKey];
}

- (IBAction)checkNowClicked:(id)sender {
    (void)sender;
    [[RCUpdateService shared] checkForUpdates];
}

@end

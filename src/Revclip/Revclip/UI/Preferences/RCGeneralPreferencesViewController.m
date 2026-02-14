//
//  RCGeneralPreferencesViewController.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCGeneralPreferencesViewController.h"

#import "RCConstants.h"
#import "RCLoginItemService.h"

static const NSInteger RCMaxHistorySizeMinimum = 1;
static const NSInteger RCMaxHistorySizeMaximum = 9999;
static const NSInteger RCMaxHistorySizeDefault = 30;
static const NSInteger RCShowStatusItemDefault = 1;

@interface RCGeneralPreferencesViewController ()

@property (nonatomic, weak) IBOutlet NSTextField *maxHistorySizeTextField;
@property (nonatomic, weak) IBOutlet NSStepper *maxHistorySizeStepper;
@property (nonatomic, weak) IBOutlet NSButton *loginAtStartupButton;
@property (nonatomic, weak) IBOutlet NSPopUpButton *showStatusItemPopUpButton;
@property (nonatomic, weak) IBOutlet NSButton *pasteCommandButton;
@property (nonatomic, weak) IBOutlet NSButton *reorderAfterPastingButton;
@property (nonatomic, weak) IBOutlet NSButton *overwriteSameHistoryButton;
@property (nonatomic, weak) IBOutlet NSButton *copySameHistoryButton;

@end

@implementation RCGeneralPreferencesViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self configureControls];
    [self applyPreferenceValues];
}

#pragma mark - Actions

- (IBAction)maxHistorySizeTextFieldChanged:(id)sender {
    (void)sender;
    [self setMaxHistorySize:self.maxHistorySizeTextField.integerValue persist:YES];
}

- (IBAction)maxHistorySizeStepperChanged:(id)sender {
    (void)sender;
    [self setMaxHistorySize:self.maxHistorySizeStepper.integerValue persist:YES];
}

- (IBAction)loginAtStartupChanged:(id)sender {
    (void)sender;
    BOOL enabled = (self.loginAtStartupButton.state == NSControlStateValueOn);
    BOOL success = [[RCLoginItemService shared] setLoginItemEnabled:enabled];
    if (success) {
        [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:loginItem];
    } else {
        self.loginAtStartupButton.state = enabled ? NSControlStateValueOff : NSControlStateValueOn;
    }
}

- (IBAction)showStatusItemChanged:(id)sender {
    (void)sender;
    NSInteger selectedIndex = self.showStatusItemPopUpButton.indexOfSelectedItem;
    NSInteger preferenceValue = (selectedIndex == 0) ? 0 : 1;
    [[NSUserDefaults standardUserDefaults] setInteger:preferenceValue
                                               forKey:kRCPrefShowStatusItemKey];
}

- (IBAction)pasteCommandChanged:(id)sender {
    (void)sender;
    [[NSUserDefaults standardUserDefaults] setBool:(self.pasteCommandButton.state == NSControlStateValueOn)
                                            forKey:kRCPrefInputPasteCommandKey];
}

- (IBAction)reorderAfterPastingChanged:(id)sender {
    (void)sender;
    [[NSUserDefaults standardUserDefaults] setBool:(self.reorderAfterPastingButton.state == NSControlStateValueOn)
                                            forKey:kRCPrefReorderClipsAfterPasting];
}

- (IBAction)overwriteSameHistoryChanged:(id)sender {
    (void)sender;
    [[NSUserDefaults standardUserDefaults] setBool:(self.overwriteSameHistoryButton.state == NSControlStateValueOn)
                                            forKey:kRCPrefOverwriteSameHistory];
}

- (IBAction)copySameHistoryChanged:(id)sender {
    (void)sender;
    [[NSUserDefaults standardUserDefaults] setBool:(self.copySameHistoryButton.state == NSControlStateValueOn)
                                            forKey:kRCPrefCopySameHistory];
}

#pragma mark - Private

- (void)configureControls {
    self.maxHistorySizeStepper.minValue = RCMaxHistorySizeMinimum;
    self.maxHistorySizeStepper.maxValue = RCMaxHistorySizeMaximum;
    self.maxHistorySizeStepper.increment = 1.0;
    self.maxHistorySizeStepper.autorepeat = YES;
    self.maxHistorySizeStepper.valueWraps = NO;

    [self.showStatusItemPopUpButton removeAllItems];
    [self.showStatusItemPopUpButton addItemsWithTitles:@[NSLocalizedString(@"Hide", nil), NSLocalizedString(@"Show", nil)]];
}

- (void)applyPreferenceValues {
    [self setMaxHistorySize:[self integerPreferenceForKey:kRCPrefMaxHistorySizeKey
                                             defaultValue:RCMaxHistorySizeDefault]
                    persist:NO];

    self.loginAtStartupButton.state = [self boolPreferenceForKey:loginItem defaultValue:NO]
        ? NSControlStateValueOn
        : NSControlStateValueOff;

    NSInteger statusItemValue = [self integerPreferenceForKey:kRCPrefShowStatusItemKey
                                                 defaultValue:RCShowStatusItemDefault];
    statusItemValue = (statusItemValue == 0) ? 0 : 1;
    [self.showStatusItemPopUpButton selectItemAtIndex:statusItemValue];

    self.pasteCommandButton.state = [self boolPreferenceForKey:kRCPrefInputPasteCommandKey defaultValue:YES]
        ? NSControlStateValueOn
        : NSControlStateValueOff;
    self.reorderAfterPastingButton.state = [self boolPreferenceForKey:kRCPrefReorderClipsAfterPasting defaultValue:YES]
        ? NSControlStateValueOn
        : NSControlStateValueOff;
    self.overwriteSameHistoryButton.state = [self boolPreferenceForKey:kRCPrefOverwriteSameHistory defaultValue:YES]
        ? NSControlStateValueOn
        : NSControlStateValueOff;
    self.copySameHistoryButton.state = [self boolPreferenceForKey:kRCPrefCopySameHistory defaultValue:YES]
        ? NSControlStateValueOn
        : NSControlStateValueOff;
}

- (void)setMaxHistorySize:(NSInteger)maxHistorySize persist:(BOOL)persist {
    NSInteger clampedValue = [self clampedMaxHistorySize:maxHistorySize];
    self.maxHistorySizeTextField.integerValue = clampedValue;
    self.maxHistorySizeStepper.integerValue = clampedValue;

    if (persist) {
        [[NSUserDefaults standardUserDefaults] setInteger:clampedValue forKey:kRCPrefMaxHistorySizeKey];
    }
}

- (NSInteger)clampedMaxHistorySize:(NSInteger)value {
    if (value < RCMaxHistorySizeMinimum) {
        return RCMaxHistorySizeMinimum;
    }
    if (value > RCMaxHistorySizeMaximum) {
        return RCMaxHistorySizeMaximum;
    }
    return value;
}

- (BOOL)boolPreferenceForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:key] == nil) {
        return defaultValue;
    }
    return [defaults boolForKey:key];
}

- (NSInteger)integerPreferenceForKey:(NSString *)key defaultValue:(NSInteger)defaultValue {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:key] == nil) {
        return defaultValue;
    }
    return [defaults integerForKey:key];
}

@end

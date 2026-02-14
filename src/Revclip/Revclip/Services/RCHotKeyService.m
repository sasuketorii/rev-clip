//
//  RCHotKeyService.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCHotKeyService.h"

#import <stdint.h>
#import <stdlib.h>

#import "RCConstants.h"
#import "RCDatabaseManager.h"

NSString * const RCHotKeyMainTriggeredNotification = @"RCHotKeyMainTriggeredNotification";
NSString * const RCHotKeyHistoryTriggeredNotification = @"RCHotKeyHistoryTriggeredNotification";
NSString * const RCHotKeySnippetTriggeredNotification = @"RCHotKeySnippetTriggeredNotification";
NSString * const RCHotKeyClearHistoryTriggeredNotification = @"RCHotKeyClearHistoryTriggeredNotification";
NSString * const RCHotKeySnippetFolderTriggeredNotification = @"RCHotKeySnippetFolderTriggeredNotification";
NSString * const RCHotKeyFolderIdentifierUserInfoKey = @"folderIdentifier";

static OSType const kRCHotKeySignature = 'RCHK';

static UInt32 const kRCHotKeyIdentifierMain = 1;
static UInt32 const kRCHotKeyIdentifierHistory = 2;
static UInt32 const kRCHotKeyIdentifierSnippet = 3;
static UInt32 const kRCHotKeyIdentifierClearHistory = 4;
static UInt32 const kRCHotKeyIdentifierSnippetFolderBase = 100;

static UInt32 const kRCKeyCodeV = 9;
static UInt32 const kRCKeyCodeB = 11;

static BOOL RCReadUInt32FromObject(id object, UInt32 *outValue) {
    if (outValue == NULL) {
        return NO;
    }

    if ([object isKindOfClass:[NSNumber class]]) {
        NSNumber *number = (NSNumber *)object;
        if (number.unsignedLongLongValue > UINT32_MAX) {
            return NO;
        }
        *outValue = (UInt32)number.unsignedIntValue;
        return YES;
    }

    if ([object isKindOfClass:[NSString class]]) {
        NSString *string = (NSString *)object;
        const char *cString = string.UTF8String;
        if (cString == NULL || *cString == '\0') {
            return NO;
        }
        char *endptr = NULL;
        unsigned long long value = strtoull(cString, &endptr, 10);
        if (endptr == cString || (endptr != NULL && *endptr != '\0')) {
            return NO;
        }
        if (value > UINT32_MAX) {
            return NO;
        }
        *outValue = (UInt32)value;
        return YES;
    }

    return NO;
}

static RCKeyCombo RCKeyComboFromDictionaryObject(id object) {
    if (![object isKindOfClass:[NSDictionary class]]) {
        return RCInvalidKeyCombo();
    }

    NSDictionary *dictionary = (NSDictionary *)object;
    UInt32 keyCode = 0;
    UInt32 modifiers = 0;
    if (!RCReadUInt32FromObject(dictionary[@"keyCode"], &keyCode)) {
        return RCInvalidKeyCombo();
    }
    if (!RCReadUInt32FromObject(dictionary[@"modifiers"], &modifiers)) {
        return RCInvalidKeyCombo();
    }

    return RCMakeKeyCombo(keyCode, modifiers);
}

static OSStatus RCHotKeyEventHandler(EventHandlerCallRef nextHandler, EventRef event, void *userData);

@interface RCHotKeyService () {
    EventHandlerRef _hotKeyEventHandlerRef;
    EventHotKeyRef _mainHotKeyRef;
    EventHotKeyRef _historyHotKeyRef;
    EventHotKeyRef _snippetHotKeyRef;
    EventHotKeyRef _clearHistoryHotKeyRef;
    NSMutableDictionary<NSString *, NSValue *> *_snippetFolderHotKeyRefs;
    NSMutableDictionary<NSString *, NSNumber *> *_snippetFolderHotKeyIdentifiers;
    NSMutableDictionary<NSNumber *, NSString *> *_snippetFolderIdentifiersByHotKeyID;
}

- (void)installHotKeyEventHandlerIfNeeded;
- (void)registerHotKeyWithCombo:(RCKeyCombo)combo
                     identifier:(UInt32)identifier
                       storeRef:(EventHotKeyRef *)hotKeyRef;
- (void)unregisterHotKeyRef:(EventHotKeyRef *)hotKeyRef;
- (void)registerSnippetFolderHotKeyWithoutPersisting:(RCKeyCombo)combo
                                  forFolderIdentifier:(NSString *)identifier;
- (void)unregisterSnippetFolderHotKeyWithoutPersisting:(NSString *)identifier;
- (void)unregisterAllSnippetFolderHotKeys;
- (BOOL)nextAvailableSnippetFolderHotKeyIdentifier:(UInt32 *)outIdentifier;
- (NSDictionary<NSString *, NSDictionary *> *)folderHotKeyCombosFromDefaults;
- (void)persistSnippetFolderHotKeyCombo:(RCKeyCombo)combo forFolderIdentifier:(NSString *)identifier;
- (void)removePersistedSnippetFolderHotKeyForIdentifier:(NSString *)identifier;
- (void)postNotificationForHotKeyIdentifier:(UInt32)identifier;
- (void)performOnMainThreadSync:(dispatch_block_t)block;

@end

@implementation RCHotKeyService

+ (instancetype)shared {
    static RCHotKeyService *sharedService = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedService = [[self alloc] init];
    });
    return sharedService;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _hotKeyEventHandlerRef = NULL;
        _mainHotKeyRef = NULL;
        _historyHotKeyRef = NULL;
        _snippetHotKeyRef = NULL;
        _clearHistoryHotKeyRef = NULL;
        _snippetFolderHotKeyRefs = [[NSMutableDictionary alloc] init];
        _snippetFolderHotKeyIdentifiers = [[NSMutableDictionary alloc] init];
        _snippetFolderIdentifiersByHotKeyID = [[NSMutableDictionary alloc] init];
        [self installHotKeyEventHandlerIfNeeded];
    }
    return self;
}

- (void)dealloc {
    [self unregisterAllHotKeys];
    if (_hotKeyEventHandlerRef != NULL) {
        RemoveEventHandler(_hotKeyEventHandlerRef);
        _hotKeyEventHandlerRef = NULL;
    }
}

#pragma mark - Public

- (void)registerMainHotKey:(RCKeyCombo)combo {
    [self performOnMainThreadSync:^{
        [self registerHotKeyWithCombo:combo
                           identifier:kRCHotKeyIdentifierMain
                             storeRef:&_mainHotKeyRef];
    }];
}

- (void)registerHistoryHotKey:(RCKeyCombo)combo {
    [self performOnMainThreadSync:^{
        [self registerHotKeyWithCombo:combo
                           identifier:kRCHotKeyIdentifierHistory
                             storeRef:&_historyHotKeyRef];
    }];
}

- (void)registerSnippetHotKey:(RCKeyCombo)combo {
    [self performOnMainThreadSync:^{
        [self registerHotKeyWithCombo:combo
                           identifier:kRCHotKeyIdentifierSnippet
                             storeRef:&_snippetHotKeyRef];
    }];
}

- (void)registerClearHistoryHotKey:(RCKeyCombo)combo {
    [self performOnMainThreadSync:^{
        [self registerHotKeyWithCombo:combo
                           identifier:kRCHotKeyIdentifierClearHistory
                             storeRef:&_clearHistoryHotKeyRef];
    }];
}

- (void)registerSnippetFolderHotKey:(RCKeyCombo)combo forFolderIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return;
    }

    [self performOnMainThreadSync:^{
        [self persistSnippetFolderHotKeyCombo:combo forFolderIdentifier:identifier];
        [self registerSnippetFolderHotKeyWithoutPersisting:combo forFolderIdentifier:identifier];
    }];
}

- (void)unregisterSnippetFolderHotKey:(NSString *)identifier {
    if (identifier.length == 0) {
        return;
    }

    [self performOnMainThreadSync:^{
        [self unregisterSnippetFolderHotKeyWithoutPersisting:identifier];
        [self removePersistedSnippetFolderHotKeyForIdentifier:identifier];
    }];
}

- (void)reloadFolderHotKeys {
    [self performOnMainThreadSync:^{
        [self unregisterAllSnippetFolderHotKeys];

        NSDictionary<NSString *, NSDictionary *> *storedCombos = [self folderHotKeyCombosFromDefaults];
        if (storedCombos.count == 0) {
            return;
        }

        NSArray<NSDictionary *> *folders = [[RCDatabaseManager shared] fetchAllSnippetFolders];
        for (NSDictionary *folder in folders) {
            NSString *identifier = [folder[@"identifier"] respondsToSelector:@selector(stringValue)]
                                 ? [folder[@"identifier"] stringValue]
                                 : @"";
            if (identifier.length == 0) {
                continue;
            }

            id enabledValue = folder[@"enabled"];
            BOOL isEnabled = YES;
            if ([enabledValue respondsToSelector:@selector(boolValue)]) {
                isEnabled = [enabledValue boolValue];
            }
            if (!isEnabled) {
                continue;
            }

            RCKeyCombo combo = RCKeyComboFromDictionaryObject(storedCombos[identifier]);
            if (!RCIsValidKeyCombo(combo)) {
                continue;
            }

            [self registerSnippetFolderHotKeyWithoutPersisting:combo forFolderIdentifier:identifier];
        }
    }];
}

- (void)unregisterAllHotKeys {
    [self performOnMainThreadSync:^{
        [self unregisterHotKeyRef:&_mainHotKeyRef];
        [self unregisterHotKeyRef:&_historyHotKeyRef];
        [self unregisterHotKeyRef:&_snippetHotKeyRef];
        [self unregisterHotKeyRef:&_clearHistoryHotKeyRef];
        [self unregisterAllSnippetFolderHotKeys];
    }];
}

- (void)loadAndRegisterHotKeysFromDefaults {
    [self performOnMainThreadSync:^{
        RCKeyCombo mainCombo = [RCHotKeyService keyComboFromUserDefaults:kRCHotKeyMainKeyCombo];
        if (!RCIsValidKeyCombo(mainCombo)) {
            mainCombo = RCMakeKeyCombo(kRCKeyCodeV, controlKey | shiftKey);
            [RCHotKeyService saveKeyCombo:mainCombo toUserDefaults:kRCHotKeyMainKeyCombo];
        }
        [self registerMainHotKey:mainCombo];

        RCKeyCombo historyCombo = [RCHotKeyService keyComboFromUserDefaults:kRCHotKeyHistoryKeyCombo];
        if (!RCIsValidKeyCombo(historyCombo)) {
            historyCombo = RCMakeKeyCombo(kRCKeyCodeV, cmdKey | controlKey);
            [RCHotKeyService saveKeyCombo:historyCombo toUserDefaults:kRCHotKeyHistoryKeyCombo];
        }
        [self registerHistoryHotKey:historyCombo];

        RCKeyCombo snippetCombo = [RCHotKeyService keyComboFromUserDefaults:kRCHotKeySnippetKeyCombo];
        if (!RCIsValidKeyCombo(snippetCombo)) {
            snippetCombo = RCMakeKeyCombo(kRCKeyCodeB, cmdKey | shiftKey);
            [RCHotKeyService saveKeyCombo:snippetCombo toUserDefaults:kRCHotKeySnippetKeyCombo];
        }
        [self registerSnippetHotKey:snippetCombo];

        RCKeyCombo clearHistoryCombo = [RCHotKeyService keyComboFromUserDefaults:kRCClearHistoryKeyCombo];
        if (RCIsValidKeyCombo(clearHistoryCombo)) {
            [self registerClearHistoryHotKey:clearHistoryCombo];
        } else {
            [self unregisterHotKeyRef:&_clearHistoryHotKeyRef];
        }

        [self reloadFolderHotKeys];
    }];
}

+ (RCKeyCombo)keyComboFromUserDefaults:(NSString *)key {
    if (key.length == 0) {
        return RCInvalidKeyCombo();
    }

    id rawValue = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return RCKeyComboFromDictionaryObject(rawValue);
}

+ (void)saveKeyCombo:(RCKeyCombo)combo toUserDefaults:(NSString *)key {
    if (key.length == 0) {
        return;
    }

    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    if (!RCIsValidKeyCombo(combo)) {
        [userDefaults removeObjectForKey:key];
        return;
    }

    NSDictionary *dictionary = @{
        @"keyCode": @(combo.keyCode),
        @"modifiers": @(combo.modifiers),
    };
    [userDefaults setObject:dictionary forKey:key];
}

+ (UInt32)carbonModifiersFromCocoaModifiers:(NSEventModifierFlags)cocoaModifiers {
    UInt32 carbonModifiers = 0;

    if ((cocoaModifiers & NSEventModifierFlagCommand) != 0) {
        carbonModifiers |= cmdKey;
    }
    if ((cocoaModifiers & NSEventModifierFlagShift) != 0) {
        carbonModifiers |= shiftKey;
    }
    if ((cocoaModifiers & NSEventModifierFlagOption) != 0) {
        carbonModifiers |= optionKey;
    }
    if ((cocoaModifiers & NSEventModifierFlagControl) != 0) {
        carbonModifiers |= controlKey;
    }

    return carbonModifiers;
}

+ (NSEventModifierFlags)cocoaModifiersFromCarbonModifiers:(UInt32)carbonModifiers {
    NSEventModifierFlags cocoaModifiers = 0;

    if ((carbonModifiers & cmdKey) != 0) {
        cocoaModifiers |= NSEventModifierFlagCommand;
    }
    if ((carbonModifiers & shiftKey) != 0) {
        cocoaModifiers |= NSEventModifierFlagShift;
    }
    if ((carbonModifiers & optionKey) != 0) {
        cocoaModifiers |= NSEventModifierFlagOption;
    }
    if ((carbonModifiers & controlKey) != 0) {
        cocoaModifiers |= NSEventModifierFlagControl;
    }

    return cocoaModifiers;
}

#pragma mark - Private

- (void)installHotKeyEventHandlerIfNeeded {
    if (_hotKeyEventHandlerRef != NULL) {
        return;
    }

    EventTypeSpec eventType;
    eventType.eventClass = kEventClassKeyboard;
    eventType.eventKind = kEventHotKeyPressed;

    OSStatus status = InstallEventHandler(GetApplicationEventTarget(),
                                          RCHotKeyEventHandler,
                                          1,
                                          &eventType,
                                          (__bridge void *)self,
                                          &_hotKeyEventHandlerRef);
    if (status != noErr) {
        NSLog(@"[RCHotKeyService] Failed to install hot key event handler (status: %d).", (int)status);
    }
}

- (void)registerHotKeyWithCombo:(RCKeyCombo)combo
                     identifier:(UInt32)identifier
                       storeRef:(EventHotKeyRef *)hotKeyRef {
    if (hotKeyRef == NULL) {
        return;
    }

    [self installHotKeyEventHandlerIfNeeded];
    [self unregisterHotKeyRef:hotKeyRef];

    if (!RCIsValidKeyCombo(combo)) {
        return;
    }

    EventHotKeyID hotKeyID;
    hotKeyID.signature = kRCHotKeySignature;
    hotKeyID.id = identifier;

    EventHotKeyRef registeredRef = NULL;
    OSStatus status = RegisterEventHotKey(combo.keyCode,
                                          combo.modifiers,
                                          hotKeyID,
                                          GetApplicationEventTarget(),
                                          0,
                                          &registeredRef);
    if (status != noErr) {
        NSLog(@"[RCHotKeyService] Failed to register hot key (id: %u, status: %d).",
              (unsigned int)identifier,
              (int)status);
        return;
    }

    *hotKeyRef = registeredRef;
}

- (void)unregisterHotKeyRef:(EventHotKeyRef *)hotKeyRef {
    if (hotKeyRef == NULL || *hotKeyRef == NULL) {
        return;
    }

    OSStatus status = UnregisterEventHotKey(*hotKeyRef);
    if (status != noErr) {
        NSLog(@"[RCHotKeyService] Failed to unregister hot key (status: %d).", (int)status);
    }
    *hotKeyRef = NULL;
}

- (void)registerSnippetFolderHotKeyWithoutPersisting:(RCKeyCombo)combo
                                  forFolderIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return;
    }

    [self installHotKeyEventHandlerIfNeeded];
    [self unregisterSnippetFolderHotKeyWithoutPersisting:identifier];

    if (!RCIsValidKeyCombo(combo)) {
        return;
    }

    UInt32 hotKeyIdentifier = 0;
    if (![self nextAvailableSnippetFolderHotKeyIdentifier:&hotKeyIdentifier]) {
        NSLog(@"[RCHotKeyService] Cannot register snippet folder hot key for '%@': no available identifier.", identifier);
        return;
    }

    EventHotKeyID hotKeyID;
    hotKeyID.signature = kRCHotKeySignature;
    hotKeyID.id = hotKeyIdentifier;

    EventHotKeyRef registeredRef = NULL;
    OSStatus status = RegisterEventHotKey(combo.keyCode,
                                          combo.modifiers,
                                          hotKeyID,
                                          GetApplicationEventTarget(),
                                          0,
                                          &registeredRef);
    if (status != noErr) {
        NSLog(@"[RCHotKeyService] Failed to register snippet folder hot key (folder: %@, id: %u, status: %d).",
              identifier,
              (unsigned int)hotKeyIdentifier,
              (int)status);
        return;
    }

    NSNumber *hotKeyNumber = @(hotKeyIdentifier);
    _snippetFolderHotKeyRefs[identifier] = [NSValue valueWithPointer:registeredRef];
    _snippetFolderHotKeyIdentifiers[identifier] = hotKeyNumber;
    _snippetFolderIdentifiersByHotKeyID[hotKeyNumber] = identifier;
}

- (void)unregisterSnippetFolderHotKeyWithoutPersisting:(NSString *)identifier {
    if (identifier.length == 0) {
        return;
    }

    NSValue *hotKeyRefValue = _snippetFolderHotKeyRefs[identifier];
    EventHotKeyRef hotKeyRef = (EventHotKeyRef)[hotKeyRefValue pointerValue];
    if (hotKeyRef != NULL) {
        OSStatus status = UnregisterEventHotKey(hotKeyRef);
        if (status != noErr) {
            NSLog(@"[RCHotKeyService] Failed to unregister snippet folder hot key (folder: %@, status: %d).",
                  identifier,
                  (int)status);
        }
    }

    NSNumber *hotKeyNumber = _snippetFolderHotKeyIdentifiers[identifier];
    if (hotKeyNumber != nil) {
        [_snippetFolderIdentifiersByHotKeyID removeObjectForKey:hotKeyNumber];
    }
    [_snippetFolderHotKeyIdentifiers removeObjectForKey:identifier];
    [_snippetFolderHotKeyRefs removeObjectForKey:identifier];
}

- (void)unregisterAllSnippetFolderHotKeys {
    NSArray<NSString *> *folderIdentifiers = [_snippetFolderHotKeyRefs.allKeys copy];
    for (NSString *identifier in folderIdentifiers) {
        [self unregisterSnippetFolderHotKeyWithoutPersisting:identifier];
    }
}

- (BOOL)nextAvailableSnippetFolderHotKeyIdentifier:(UInt32 *)outIdentifier {
    if (outIdentifier == NULL) {
        return NO;
    }

    UInt32 candidate = kRCHotKeyIdentifierSnippetFolderBase;
    while (_snippetFolderIdentifiersByHotKeyID[@(candidate)] != nil) {
        if (candidate == UINT32_MAX) {
            NSLog(@"[RCHotKeyService] Snippet folder hot key identifier space exhausted.");
            return NO;
        }
        candidate++;
    }

    *outIdentifier = candidate;
    return YES;
}

- (NSDictionary<NSString *, NSDictionary *> *)folderHotKeyCombosFromDefaults {
    id rawValue = [[NSUserDefaults standardUserDefaults] objectForKey:kRCFolderKeyCombos];
    if (![rawValue isKindOfClass:[NSDictionary class]]) {
        return @{};
    }

    NSDictionary *dictionary = (NSDictionary *)rawValue;
    NSMutableDictionary<NSString *, NSDictionary *> *validated = [NSMutableDictionary dictionary];
    for (id key in dictionary) {
        if (![key isKindOfClass:[NSString class]]) {
            continue;
        }
        id comboDictionary = dictionary[key];
        if (![comboDictionary isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        validated[(NSString *)key] = (NSDictionary *)comboDictionary;
    }
    return [validated copy];
}

- (void)persistSnippetFolderHotKeyCombo:(RCKeyCombo)combo forFolderIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return;
    }

    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary<NSString *, NSDictionary *> *mutableCombos = [[self folderHotKeyCombosFromDefaults] mutableCopy];
    if (mutableCombos == nil) {
        mutableCombos = [NSMutableDictionary dictionary];
    }

    if (RCIsValidKeyCombo(combo)) {
        mutableCombos[identifier] = @{
            @"keyCode": @(combo.keyCode),
            @"modifiers": @(combo.modifiers),
        };
    } else {
        [mutableCombos removeObjectForKey:identifier];
    }

    if (mutableCombos.count == 0) {
        [userDefaults removeObjectForKey:kRCFolderKeyCombos];
        return;
    }

    [userDefaults setObject:[mutableCombos copy] forKey:kRCFolderKeyCombos];
}

- (void)removePersistedSnippetFolderHotKeyForIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return;
    }

    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary<NSString *, NSDictionary *> *mutableCombos = [[self folderHotKeyCombosFromDefaults] mutableCopy];
    [mutableCombos removeObjectForKey:identifier];

    if (mutableCombos.count == 0) {
        [userDefaults removeObjectForKey:kRCFolderKeyCombos];
        return;
    }

    [userDefaults setObject:[mutableCombos copy] forKey:kRCFolderKeyCombos];
}

- (void)postNotificationForHotKeyIdentifier:(UInt32)identifier {
    NSString *notificationName = nil;
    NSDictionary *userInfo = nil;

    switch (identifier) {
        case kRCHotKeyIdentifierMain:
            notificationName = RCHotKeyMainTriggeredNotification;
            break;
        case kRCHotKeyIdentifierHistory:
            notificationName = RCHotKeyHistoryTriggeredNotification;
            break;
        case kRCHotKeyIdentifierSnippet:
            notificationName = RCHotKeySnippetTriggeredNotification;
            break;
        case kRCHotKeyIdentifierClearHistory:
            notificationName = RCHotKeyClearHistoryTriggeredNotification;
            break;
        default:
        {
            __block NSString *folderIdentifier = nil;
            [self performOnMainThreadSync:^{
                folderIdentifier = _snippetFolderIdentifiersByHotKeyID[@(identifier)];
            }];
            if (folderIdentifier.length > 0) {
                notificationName = RCHotKeySnippetFolderTriggeredNotification;
                userInfo = @{ RCHotKeyFolderIdentifierUserInfoKey: folderIdentifier };
            }
            break;
        }
    }

    if (notificationName.length == 0) {
        return;
    }

    dispatch_block_t postBlock = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:notificationName
                                                            object:self
                                                          userInfo:userInfo];
    };

    if ([NSThread isMainThread]) {
        postBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), postBlock);
    }
}

- (void)performOnMainThreadSync:(dispatch_block_t)block {
    if (block == nil) {
        return;
    }

    if ([NSThread isMainThread]) {
        block();
        return;
    }

    dispatch_sync(dispatch_get_main_queue(), block);
}

@end

static OSStatus RCHotKeyEventHandler(EventHandlerCallRef nextHandler, EventRef event, void *userData) {
    (void)nextHandler;

    if (event == NULL || userData == NULL) {
        return eventNotHandledErr;
    }

    EventHotKeyID hotKeyID;
    OSStatus status = GetEventParameter(event,
                                        kEventParamDirectObject,
                                        typeEventHotKeyID,
                                        NULL,
                                        sizeof(EventHotKeyID),
                                        NULL,
                                        &hotKeyID);
    if (status != noErr) {
        return status;
    }

    if (hotKeyID.signature != kRCHotKeySignature) {
        return eventNotHandledErr;
    }

    RCHotKeyService *service = (__bridge RCHotKeyService *)userData;
    [service postNotificationForHotKeyIdentifier:hotKeyID.id];
    return noErr;
}

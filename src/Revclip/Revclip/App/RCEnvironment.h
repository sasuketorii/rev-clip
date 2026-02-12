//
//  RCEnvironment.h
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class RCClipboardService;
@class RCPasteService;
@class RCHotKeyService;
@class RCAccessibilityService;
@class RCExcludeAppService;
@class RCDataCleanService;
@class RCLoginItemService;
@class RCMenuManager;
@class RCDatabaseManager;

@interface RCEnvironment : NSObject

+ (instancetype)shared;

// Services
@property (nonatomic, strong, nullable) id clipboardService;       // RCClipboardService
@property (nonatomic, strong, nullable) id pasteService;           // RCPasteService
@property (nonatomic, strong, nullable) id hotKeyService;          // RCHotKeyService
@property (nonatomic, strong, nullable) id accessibilityService;   // RCAccessibilityService
@property (nonatomic, strong, nullable) id excludeAppService;      // RCExcludeAppService
@property (nonatomic, strong, nullable) id dataCleanService;       // RCDataCleanService
@property (nonatomic, strong, nullable) id loginItemService;       // RCLoginItemService

// Managers
@property (nonatomic, strong, nullable) id menuManager;            // RCMenuManager
@property (nonatomic, strong, nullable) id databaseManager;        // RCDatabaseManager

@end

NS_ASSUME_NONNULL_END

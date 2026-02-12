//
//  RCLoginItemService.h
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RCLoginItemService : NSObject

+ (instancetype)shared;

// ログインアイテムの状態
@property (nonatomic, readonly, getter=isLoginItemEnabled) BOOL loginItemEnabled;

// ログインアイテムの有効/無効切り替え
- (BOOL)setLoginItemEnabled:(BOOL)enabled;

@end

NS_ASSUME_NONNULL_END

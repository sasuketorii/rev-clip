//
//  RCUpdateService.h
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RCUpdateService : NSObject

+ (instancetype)shared;

/// Sparkle の SPUStandardUpdaterController を初期化
- (void)setupUpdater;

/// 手動アップデートチェック
- (void)checkForUpdates;

/// アップデートチェック可能かどうか
@property (nonatomic, readonly) BOOL canCheckForUpdates;

/// 自動チェックの有効/無効
@property (nonatomic, assign, getter=isAutomaticallyChecksForUpdates) BOOL automaticallyChecksForUpdates;

/// アップデート間隔（秒）
@property (nonatomic, assign) NSTimeInterval updateCheckInterval;

@end

NS_ASSUME_NONNULL_END

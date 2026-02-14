//
//  RCDataCleanService.h
//  Revpy
//
//  Copyright (c) 2024-2026 Revpy. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RCDataCleanService : NSObject

+ (instancetype)shared;

// クリーンアップタイマーの開始・停止
- (void)startCleanupTimer;
- (void)stopCleanupTimer;

// 手動クリーンアップ実行
- (void)performCleanup;

@end

NS_ASSUME_NONNULL_END

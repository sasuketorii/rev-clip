//
//  RCClipboardService.h
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface RCClipboardService : NSObject

+ (instancetype)shared;

// 監視の開始・停止
- (void)startMonitoring;
- (void)stopMonitoring;
@property (nonatomic, readonly) BOOL isMonitoring;

// 手動での最新クリップ取得
- (void)captureCurrentClipboard;

@end

// 通知名
extern NSString * const RCClipboardDidChangeNotification;

NS_ASSUME_NONNULL_END

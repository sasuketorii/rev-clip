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
@property (atomic, readonly) BOOL isMonitoring;

// 内部ペースト操作中フラグ（RCPasteService がペースト中にクリップボード変更検知を抑制する）
@property (atomic, assign) BOOL isPastingInternally;

// 手動での最新クリップ取得
- (void)captureCurrentClipboard;

@end

// 通知名
extern NSString * const RCClipboardDidChangeNotification;

NS_ASSUME_NONNULL_END

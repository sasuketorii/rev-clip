//
//  RCPasteService.h
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class RCClipData;

@interface RCPasteService : NSObject

+ (instancetype)shared;

// RCClipDataをペーストボードに設定してアクティブアプリに貼り付け
- (void)pasteClipData:(RCClipData *)clipData;

// プレーンテキストとしてペースト
- (void)pastePlainText:(NSString *)text;

// Cmd+Vキーイベントを送信
- (void)sendPasteKeyStroke;

@end

NS_ASSUME_NONNULL_END

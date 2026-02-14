//
//  RCPrivacyService.h
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RCClipboardAccessState) {
    RCClipboardAccessStateUnknown = 0,
    RCClipboardAccessStateGranted,
    RCClipboardAccessStateDenied,
    RCClipboardAccessStateNotDetermined,
};

@interface RCPrivacyService : NSObject

+ (instancetype)shared;

// 現在のクリップボードアクセス状態を取得（副作用なし）
- (RCClipboardAccessState)clipboardAccessState;

// クリップボードアクセス状態をリフレッシュし、変更があれば通知を送信
- (void)refreshClipboardAccessState;

// クリップボードアクセスが可能かチェック
- (BOOL)canAccessClipboard;

// macOS 15.4+ のプライバシーAPIが利用可能か
- (BOOL)isClipboardPrivacyAPIAvailable;

// クリップボードの内容パターンを検出（読み取りなし）
- (void)detectClipboardPatternsWithCompletion:(void (^)(NSSet<NSString *> * _Nullable patterns, NSError * _Nullable error))completion;

// ユーザーにクリップボードアクセスの許可を促すガイダンスを表示
- (void)showClipboardAccessGuidance;

@end

// 通知名
extern NSString * const RCClipboardAccessStateDidChangeNotification;

NS_ASSUME_NONNULL_END

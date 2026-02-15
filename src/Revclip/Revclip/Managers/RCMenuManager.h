//
//  RCMenuManager.h
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface RCMenuManager : NSObject

+ (instancetype)shared;

// ステータスバーアイテムのセットアップ
- (void)setupStatusItem;

// メニューの再構築
- (void)rebuildMenu;

@end

NS_ASSUME_NONNULL_END

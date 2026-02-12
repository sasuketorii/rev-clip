//
//  RCExcludeAppService.h
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RCExcludeAppService : NSObject

+ (instancetype)shared;

// 現在のフロントアプリが除外対象か判定
- (BOOL)shouldExcludeCurrentApp;

// 除外アプリリストの取得・設定
- (NSArray<NSString *> *)excludedBundleIdentifiers;
- (void)setExcludedBundleIdentifiers:(NSArray<NSString *> *)identifiers;

// 除外アプリの追加・削除
- (void)addExcludedBundleIdentifier:(NSString *)bundleId;
- (void)removeExcludedBundleIdentifier:(NSString *)bundleId;

@end

NS_ASSUME_NONNULL_END

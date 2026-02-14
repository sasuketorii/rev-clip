//
//  RCMoveToApplicationsService.h
//  Revpy
//
//  Copyright (c) 2024-2026 Revpy. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RCMoveToApplicationsService : NSObject

+ (instancetype)shared;

/// アプリが /Applications に存在するかチェックし、必要なら移動を提案
/// applicationDidFinishLaunching: から一度だけ呼ぶ
- (void)checkAndMoveIfNeeded;

@end

NS_ASSUME_NONNULL_END

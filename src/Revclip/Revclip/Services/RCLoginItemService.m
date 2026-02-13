//
//  RCLoginItemService.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCLoginItemService.h"

#import <ServiceManagement/ServiceManagement.h>

@implementation RCLoginItemService

+ (instancetype)shared {
    static RCLoginItemService *sharedService = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedService = [[self alloc] init];
    });
    return sharedService;
}

- (BOOL)isLoginItemEnabled {
    return ([SMAppService mainAppService].status == SMAppServiceStatusEnabled);
}

- (BOOL)setLoginItemEnabled:(BOOL)enabled {
    SMAppService *service = [SMAppService mainAppService];
    NSError *error = nil;
    BOOL success = NO;

    if (enabled) {
        success = [service registerAndReturnError:&error];
    } else {
        success = [service unregisterAndReturnError:&error];
    }

    if (!success) {
        NSLog(@"[RCLoginItemService] Failed to %@ login item: %@",
              enabled ? @"enable" : @"disable",
              error.localizedDescription ?: @"Unknown error");
    }

    return success;
}

@end

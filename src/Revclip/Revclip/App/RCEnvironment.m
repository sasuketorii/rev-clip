//
//  RCEnvironment.m
//  Revpy
//
//  Copyright (c) 2024-2026 Revpy. All rights reserved.
//

#import "RCEnvironment.h"

@implementation RCEnvironment

+ (instancetype)shared {
    static RCEnvironment *sharedEnvironment = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedEnvironment = [[RCEnvironment alloc] init];
    });
    return sharedEnvironment;
}

@end

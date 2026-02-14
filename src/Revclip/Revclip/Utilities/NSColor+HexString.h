//
//  NSColor+HexString.h
//  Revpy
//
//  Copyright (c) 2024-2026 Revpy. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSColor (HexString)

+ (nullable NSColor *)colorWithHexString:(NSString *)hexString;
- (nullable NSString *)hexString;
+ (BOOL)isValidHexColorString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END

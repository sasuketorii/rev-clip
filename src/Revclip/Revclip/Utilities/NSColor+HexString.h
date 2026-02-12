//
//  NSColor+HexString.h
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSColor (HexString)

+ (nullable NSColor *)colorWithHexString:(NSString *)hexString;
- (NSString *)hexString;
+ (BOOL)isValidHexColorString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END

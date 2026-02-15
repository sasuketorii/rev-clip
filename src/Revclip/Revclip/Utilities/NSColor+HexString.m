//
//  NSColor+HexString.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "NSColor+HexString.h"

static NSString *RCNormalizedHexColorString(NSString *input) {
    if (input.length == 0) {
        return @"";
    }

    NSString *normalized = [[input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if ([normalized hasPrefix:@"#"]) {
        normalized = [normalized substringFromIndex:1];
    } else if ([normalized hasPrefix:@"0X"]) {
        normalized = [normalized substringFromIndex:2];
    }
    return normalized;
}

static BOOL RCIsHexCharactersOnly(NSString *value) {
    if (value.length == 0) {
        return NO;
    }

    NSCharacterSet *nonHexSet = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEF"] invertedSet];
    return [value rangeOfCharacterFromSet:nonHexSet].location == NSNotFound;
}

static CGFloat RCColorComponentFromHexPair(NSString *hexPair) {
    if (hexPair.length < 2) {
        return 0.0;
    }

    unsigned int value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hexPair];
    [scanner scanHexInt:&value];
    return (CGFloat)value / 255.0;
}

@implementation NSColor (HexString)

+ (NSColor *)colorWithHexString:(NSString *)hexString {
    if (![self isValidHexColorString:hexString]) {
        return nil;
    }

    NSString *normalized = RCNormalizedHexColorString(hexString);
    NSString *redHex = nil;
    NSString *greenHex = nil;
    NSString *blueHex = nil;
    NSString *alphaHex = @"FF";

    switch (normalized.length) {
        case 3: {
            NSString *r = [normalized substringWithRange:NSMakeRange(0, 1)];
            NSString *g = [normalized substringWithRange:NSMakeRange(1, 1)];
            NSString *b = [normalized substringWithRange:NSMakeRange(2, 1)];
            redHex = [r stringByAppendingString:r];
            greenHex = [g stringByAppendingString:g];
            blueHex = [b stringByAppendingString:b];
            break;
        }
        case 4: {
            NSString *r = [normalized substringWithRange:NSMakeRange(0, 1)];
            NSString *g = [normalized substringWithRange:NSMakeRange(1, 1)];
            NSString *b = [normalized substringWithRange:NSMakeRange(2, 1)];
            NSString *a = [normalized substringWithRange:NSMakeRange(3, 1)];
            redHex = [r stringByAppendingString:r];
            greenHex = [g stringByAppendingString:g];
            blueHex = [b stringByAppendingString:b];
            alphaHex = [a stringByAppendingString:a];
            break;
        }
        case 6:
            redHex = [normalized substringWithRange:NSMakeRange(0, 2)];
            greenHex = [normalized substringWithRange:NSMakeRange(2, 2)];
            blueHex = [normalized substringWithRange:NSMakeRange(4, 2)];
            break;
        case 8:
            redHex = [normalized substringWithRange:NSMakeRange(0, 2)];
            greenHex = [normalized substringWithRange:NSMakeRange(2, 2)];
            blueHex = [normalized substringWithRange:NSMakeRange(4, 2)];
            alphaHex = [normalized substringWithRange:NSMakeRange(6, 2)];
            break;
        default:
            return nil;
    }

    CGFloat red = RCColorComponentFromHexPair(redHex);
    CGFloat green = RCColorComponentFromHexPair(greenHex);
    CGFloat blue = RCColorComponentFromHexPair(blueHex);
    CGFloat alpha = RCColorComponentFromHexPair(alphaHex);

    return [NSColor colorWithSRGBRed:red green:green blue:blue alpha:alpha];
}

- (NSString *)hexString {
    NSColor *srgbColor = [self colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (srgbColor == nil) {
        return nil;
    }

    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    CGFloat alpha = 0.0;
    [srgbColor getRed:&red green:&green blue:&blue alpha:&alpha];

    NSUInteger redByte = (NSUInteger)lround(MAX(0.0, MIN(1.0, red)) * 255.0);
    NSUInteger greenByte = (NSUInteger)lround(MAX(0.0, MIN(1.0, green)) * 255.0);
    NSUInteger blueByte = (NSUInteger)lround(MAX(0.0, MIN(1.0, blue)) * 255.0);
    NSUInteger alphaByte = (NSUInteger)lround(MAX(0.0, MIN(1.0, alpha)) * 255.0);

    if (alphaByte < 255) {
        return [NSString stringWithFormat:@"#%02lX%02lX%02lX%02lX",
                (unsigned long)redByte,
                (unsigned long)greenByte,
                (unsigned long)blueByte,
                (unsigned long)alphaByte];
    }

    return [NSString stringWithFormat:@"#%02lX%02lX%02lX",
            (unsigned long)redByte,
            (unsigned long)greenByte,
            (unsigned long)blueByte];
}

+ (BOOL)isValidHexColorString:(NSString *)string {
    NSString *normalized = RCNormalizedHexColorString(string);
    NSUInteger length = normalized.length;
    if (!(length == 3 || length == 4 || length == 6 || length == 8)) {
        return NO;
    }

    return RCIsHexCharactersOnly(normalized);
}

@end

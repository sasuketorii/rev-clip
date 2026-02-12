//
//  NSImage+Color.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "NSImage+Color.h"

@implementation NSImage (Color)

+ (NSImage *)imageWithColor:(NSColor *)color size:(NSSize)size {
    return [self imageWithColor:color size:size cornerRadius:0.0];
}

+ (NSImage *)imageWithColor:(NSColor *)color size:(NSSize)size cornerRadius:(CGFloat)radius {
    CGFloat width = MAX(size.width, 1.0);
    CGFloat height = MAX(size.height, 1.0);
    NSRect drawRect = NSMakeRect(0, 0, width, height);

    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
    [image lockFocus];
    [color setFill];

    CGFloat maxRadius = MIN(width, height) / 2.0;
    CGFloat clampedRadius = MAX(0.0, MIN(radius, maxRadius));
    if (clampedRadius > 0.0) {
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:drawRect xRadius:clampedRadius yRadius:clampedRadius];
        [path fill];
    } else {
        NSRectFill(drawRect);
    }

    [image unlockFocus];
    return image;
}

@end

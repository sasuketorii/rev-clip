//
//  NSImage+Resize.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "NSImage+Resize.h"

@implementation NSImage (Resize)

- (NSImage *)resizedImageToSize:(NSSize)targetSize {
    if (targetSize.width <= 0.0 || targetSize.height <= 0.0) {
        return nil;
    }
    if (self.size.width <= 0.0 || self.size.height <= 0.0) {
        return nil;
    }

    NSImage *sourceImage = self;
    NSImage *resizedImage = [NSImage imageWithSize:targetSize flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];

        NSRect sourceRect = NSMakeRect(0, 0, sourceImage.size.width, sourceImage.size.height);
        [sourceImage drawInRect:dstRect
                       fromRect:sourceRect
                      operation:NSCompositingOperationCopy
                       fraction:1.0
                 respectFlipped:YES
                          hints:nil];
        return YES;
    }];

    resizedImage.template = self.template;
    return resizedImage;
}

- (NSImage *)resizedImageToFitSize:(NSSize)maxSize {
    if (maxSize.width <= 0.0 || maxSize.height <= 0.0) {
        return nil;
    }
    if (self.size.width <= 0.0 || self.size.height <= 0.0) {
        return nil;
    }

    CGFloat widthRatio = maxSize.width / self.size.width;
    CGFloat heightRatio = maxSize.height / self.size.height;
    CGFloat scale = MIN(widthRatio, heightRatio);
    if (scale <= 0.0) {
        return nil;
    }

    if (scale > 1.0) {
        scale = 1.0;
    }

    NSSize targetSize = NSMakeSize(self.size.width * scale, self.size.height * scale);
    return [self resizedImageToSize:targetSize];
}

@end

//
//  NSImage+Resize.h
//  Revpy
//
//  Copyright (c) 2024-2026 Revpy. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSImage (Resize)

- (nullable NSImage *)resizedImageToSize:(NSSize)targetSize;
- (nullable NSImage *)resizedImageToFitSize:(NSSize)maxSize;

@end

NS_ASSUME_NONNULL_END

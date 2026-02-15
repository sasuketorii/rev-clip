//
//  NSImage+Resize.h
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSImage (Resize)

- (nullable NSImage *)resizedImageToSize:(NSSize)targetSize;
- (nullable NSImage *)resizedImageToFitSize:(NSSize)maxSize;

@end

NS_ASSUME_NONNULL_END

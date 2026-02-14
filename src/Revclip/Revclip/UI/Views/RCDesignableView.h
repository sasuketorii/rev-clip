//
//  RCDesignableView.h
//  Revpy
//
//  Copyright (c) 2024-2026 Revpy. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

IB_DESIGNABLE
@interface RCDesignableView : NSView

@property (nonatomic, strong) IBInspectable NSColor *viewBackgroundColor;
@property (nonatomic, assign) IBInspectable CGFloat cornerRadius;
@property (nonatomic, strong) IBInspectable NSColor *borderColor;
@property (nonatomic, assign) IBInspectable CGFloat borderWidth;

@end

NS_ASSUME_NONNULL_END

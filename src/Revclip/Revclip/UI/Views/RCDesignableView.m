//
//  RCDesignableView.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCDesignableView.h"

@interface RCDesignableView ()

- (void)rc_commonInit;
- (void)rc_applyLayerStyle;
- (CGFloat)rc_clampedCornerRadiusForRect:(NSRect)rect;

@end

@implementation RCDesignableView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self rc_commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self rc_commonInit];
    }
    return self;
}

- (void)prepareForInterfaceBuilder {
    [super prepareForInterfaceBuilder];
    [self rc_applyLayerStyle];
    [self setNeedsDisplay:YES];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self rc_applyLayerStyle];
}

- (void)setBackgroundColor:(NSColor *)backgroundColor {
    _backgroundColor = backgroundColor ?: [NSColor clearColor];
    [self rc_applyLayerStyle];
    [self setNeedsDisplay:YES];
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = MAX(cornerRadius, 0.0);
    [self rc_applyLayerStyle];
    [self setNeedsDisplay:YES];
}

- (void)setBorderColor:(NSColor *)borderColor {
    _borderColor = borderColor ?: [NSColor clearColor];
    [self rc_applyLayerStyle];
    [self setNeedsDisplay:YES];
}

- (void)setBorderWidth:(CGFloat)borderWidth {
    _borderWidth = MAX(borderWidth, 0.0);
    [self rc_applyLayerStyle];
    [self setNeedsDisplay:YES];
}

#pragma mark - Private

- (void)rc_commonInit {
    _backgroundColor = [NSColor clearColor];
    _cornerRadius = 0.0;
    _borderColor = [NSColor clearColor];
    _borderWidth = 0.0;

    self.wantsLayer = YES;
    [self rc_applyLayerStyle];
}

- (void)rc_applyLayerStyle {
    CALayer *targetLayer = self.layer;
    if (targetLayer == nil) {
        return;
    }

    CGFloat clampedBorderWidth = MAX(self.borderWidth, 0.0);
    CGFloat cornerRadius = [self rc_clampedCornerRadiusForRect:self.bounds];

    targetLayer.backgroundColor = self.backgroundColor.CGColor;
    targetLayer.cornerRadius = cornerRadius;
    targetLayer.borderWidth = clampedBorderWidth;
    targetLayer.borderColor = self.borderColor.CGColor;
    targetLayer.masksToBounds = (cornerRadius > 0.0);
}

- (CGFloat)rc_clampedCornerRadiusForRect:(NSRect)rect {
    CGFloat maxRadius = MIN(rect.size.width, rect.size.height) / 2.0;
    return MAX(0.0, MIN(self.cornerRadius, maxRadius));
}

@end

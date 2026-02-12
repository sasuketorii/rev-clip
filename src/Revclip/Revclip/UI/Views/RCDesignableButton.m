//
//  RCDesignableButton.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCDesignableButton.h"

@interface RCDesignableButton ()

@property (nonatomic, strong, nullable) NSTrackingArea *hoverTrackingArea;
@property (nonatomic, assign) BOOL isMouseInside;

- (void)rc_commonInit;
- (void)rc_applyLayerStyle;
- (void)rc_updateHoverStateFromCurrentMouseLocation;
- (NSColor *)rc_currentBackgroundColor;
- (CGFloat)rc_clampedCornerRadius;

@end

@implementation RCDesignableButton

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
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self rc_applyLayerStyle];
}

- (void)updateTrackingAreas {
    if (self.hoverTrackingArea != nil) {
        [self removeTrackingArea:self.hoverTrackingArea];
    }

    NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited
                                    | NSTrackingInVisibleRect
                                    | NSTrackingActiveInActiveApp
                                    | NSTrackingAssumeInside;
    self.hoverTrackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                           options:options
                                                             owner:self
                                                          userInfo:nil];
    [self addTrackingArea:self.hoverTrackingArea];

    [super updateTrackingAreas];
    [self rc_updateHoverStateFromCurrentMouseLocation];
}

- (void)mouseEntered:(NSEvent *)event {
    [super mouseEntered:event];
    self.isMouseInside = YES;
    [self rc_applyLayerStyle];
}

- (void)mouseExited:(NSEvent *)event {
    [super mouseExited:event];
    self.isMouseInside = NO;
    [self rc_applyLayerStyle];
}

- (void)setButtonBackgroundColor:(NSColor *)buttonBackgroundColor {
    _buttonBackgroundColor = buttonBackgroundColor ?: [NSColor clearColor];
    [self rc_applyLayerStyle];
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = MAX(cornerRadius, 0.0);
    [self rc_applyLayerStyle];
}

- (void)setBorderColor:(NSColor *)borderColor {
    _borderColor = borderColor ?: [NSColor clearColor];
    [self rc_applyLayerStyle];
}

- (void)setBorderWidth:(CGFloat)borderWidth {
    _borderWidth = MAX(borderWidth, 0.0);
    [self rc_applyLayerStyle];
}

- (void)setHoverBackgroundColor:(nullable NSColor *)hoverBackgroundColor {
    _hoverBackgroundColor = hoverBackgroundColor;
    [self rc_applyLayerStyle];
}

#pragma mark - Private

- (void)rc_commonInit {
    _buttonBackgroundColor = [NSColor clearColor];
    _cornerRadius = 0.0;
    _borderColor = [NSColor clearColor];
    _borderWidth = 0.0;
    _hoverBackgroundColor = nil;
    _isMouseInside = NO;

    self.wantsLayer = YES;
    self.bordered = NO;
    [self rc_applyLayerStyle];
}

- (void)rc_applyLayerStyle {
    CALayer *targetLayer = self.layer;
    if (targetLayer == nil) {
        return;
    }

    CGFloat cornerRadius = [self rc_clampedCornerRadius];
    targetLayer.backgroundColor = [self rc_currentBackgroundColor].CGColor;
    targetLayer.cornerRadius = cornerRadius;
    targetLayer.borderColor = self.borderColor.CGColor;
    targetLayer.borderWidth = MAX(self.borderWidth, 0.0);
    targetLayer.masksToBounds = (cornerRadius > 0.0);
}

- (void)rc_updateHoverStateFromCurrentMouseLocation {
    NSWindow *window = self.window;
    BOOL isInside = NO;
    if (window != nil) {
        NSPoint mouseLocationInWindow = window.mouseLocationOutsideOfEventStream;
        NSPoint mouseLocationInView = [self convertPoint:mouseLocationInWindow fromView:nil];
        isInside = NSPointInRect(mouseLocationInView, self.bounds);
    }

    if (self.isMouseInside != isInside) {
        self.isMouseInside = isInside;
        [self rc_applyLayerStyle];
    }
}

- (NSColor *)rc_currentBackgroundColor {
    if (self.isMouseInside) {
        return self.hoverBackgroundColor ?: self.buttonBackgroundColor;
    }
    return self.buttonBackgroundColor ?: [NSColor clearColor];
}

- (CGFloat)rc_clampedCornerRadius {
    CGFloat maxRadius = MIN(NSWidth(self.bounds), NSHeight(self.bounds)) / 2.0;
    return MAX(0.0, MIN(self.cornerRadius, maxRadius));
}

@end

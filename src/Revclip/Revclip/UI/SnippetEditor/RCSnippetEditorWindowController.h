//
//  RCSnippetEditorWindowController.h
//  Revpy
//
//  Copyright (c) 2024-2026 Revpy. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface RCSnippetEditorWindowController : NSWindowController

+ (instancetype)shared;
- (void)showWindow:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END

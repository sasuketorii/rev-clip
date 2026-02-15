//
//  RCAppDelegate.h
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface RCAppDelegate : NSObject <NSApplicationDelegate>

- (IBAction)showPreferencesWindow:(id)sender;
- (IBAction)showPreferences:(id)sender;
- (IBAction)showSnippetEditor:(id)sender;
- (IBAction)importSnippets:(id)sender;
- (IBAction)exportSnippets:(id)sender;

@end

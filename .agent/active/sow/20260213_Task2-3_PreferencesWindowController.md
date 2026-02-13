# SOW: Task 2-3 Preferences Window Controller

## 概要
- `RCPreferencesWindowController` を新規実装し、`NSToolbar` ベースの7タブ切替（General/Menu/Type/Exclude/Shortcuts/Updates/Beta）を追加。
- タブごとの `NSViewController` プレースホルダーと手書きXIBを追加。
- タブ切替時のビュー差し替え + ウィンドウアニメーションリサイズを実装。
- `RCAppDelegate` に `showPreferencesWindow:` と `showPreferences:` を追加し、既存メニュー経路からPreferences表示可能にした。

## 実施内容
- `src/Revclip/Revclip/UI/Preferences/RCPreferencesWindowController.h/.m` を新規追加:
  - singleton (`shared`)
  - タブ識別子定数（7種）
  - `NSToolbarDelegate` 実装
  - SF Symbols設定（gearshape/list.bullet/doc.on.doc/xmark.app/keyboard/arrow.triangle.2.circlepath/flask）
  - lazyロードで各ViewController生成
  - `switchToViewController:` によるサイズアニメーション付き切替
  - `NSWindowStyleMaskTitled | NSWindowStyleMaskClosable`、`NSWindowCollectionBehaviorMoveToActiveSpace`、`releasedWhenClosed = NO`、初回中央配置
- `src/Revclip/Revclip/UI/Preferences/` にプレースホルダー追加:
  - `RCGeneralPreferencesViewController.h/.m` + `RCGeneralPreferencesView.xib` (480x300)
  - `RCMenuPreferencesViewController.h/.m` + `RCMenuPreferencesView.xib` (480x420)
  - `RCTypePreferencesViewController.h/.m` + `RCTypePreferencesView.xib` (480x280)
  - `RCExcludePreferencesViewController.h/.m` + `RCExcludePreferencesView.xib` (480x350)
  - `RCShortcutsPreferencesViewController.h/.m` + `RCShortcutsPreferencesView.xib` (480x280)
  - `RCUpdatesPreferencesViewController.h/.m` + `RCUpdatesPreferencesView.xib` (480x200)
  - `RCBetaPreferencesViewController.h/.m` + `RCBetaPreferencesView.xib` (480x380)
- `src/Revclip/Revclip/UI/Preferences/RCPreferencesWindow.xib` を新規追加（File's Owner=RCPreferencesWindowController、window outlet接続）。
- `src/Revclip/Revclip/App/RCAppDelegate.m`:
  - `#import "RCPreferencesWindowController.h"` を追加
  - `showPreferencesWindow:` / `showPreferences:` 実装を追加
- `cd src/Revclip && xcodegen generate` を実行し、`Revclip.xcodeproj/project.pbxproj` を更新。
- `project.yml` は `sources: - path: Revclip` で `Revclip/UI/Preferences/**` を既に包含しており、追加変更不要を確認。

## 検証結果
- `xcodegen generate`: 成功
- 構文チェック（PASS）:
  - `xcrun clang -fobjc-arc -fsyntax-only -fmodules -IRevclip -IRevclip/App -IRevclip/Services -IRevclip/Managers -IRevclip/Utilities -IRevclip/UI/Preferences Revclip/App/RCAppDelegate.m`
  - `for f in Revclip/UI/Preferences/*.m; do xcrun clang -fobjc-arc -fsyntax-only -fmodules -IRevclip -IRevclip/UI/Preferences "$f"; done`
- XIB妥当性:
  - `ibtool` は環境上利用不可（`xcrun: error: unable to find utility "ibtool"`）
  - 代替で `xmllint --noout Revclip/UI/Preferences/*.xib` は全件成功

## 例外・省略
- Worktree作成は省略: ユーザーから「メインブランチで作業してOK」の明示許可あり。
- Blueprint/TDDは省略: ユーザー指示でテストはPhase 3で一括実施。

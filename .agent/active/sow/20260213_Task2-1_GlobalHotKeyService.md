# SOW: Task 2-1 グローバルホットキーサービス

## 概要
- Carbon API (`RegisterEventHotKey` / `UnregisterEventHotKey`) を直接使用する `RCHotKeyService` を追加。
- メイン/履歴/スニペット/履歴クリアの4系統ホットキー登録・解除と、通知発火を実装。
- `RCAppDelegate` にホットキー初期化/終了時解除を接続し、`RCEnvironment` へDI登録。
- `RCMenuManager` にホットキー通知監視を追加し、メニュー表示・履歴クリア動作に接続。
- `project.yml` に `Carbon.framework` を追加し、`xcodegen generate` を実行。

## 実施内容
- `src/Revclip/Revclip/Services/RCHotKeyService.h` を新規追加:
  - `RCKeyCombo` 構造体定義
  - 4種類のホットキー登録API
  - 全解除API
  - UserDefaults変換API
  - Cocoa/Carbon修飾キー変換API
  - 4種類の通知名定義
- `src/Revclip/Revclip/Services/RCHotKeyService.m` を新規追加:
  - `InstallEventHandler(GetApplicationEventTarget(), ...)` によるハンドラ登録
  - `kEventClassKeyboard` / `kEventHotKeyPressed` 処理
  - `EventHotKeyID.signature = 'RCHK'`
  - `EventHotKeyID.id = 1/2/3/4` で種別識別
  - 各ホットキーの `RegisterEventHotKey` / `UnregisterEventHotKey`
  - 通知 (`NSNotificationCenter`) 発火
  - UserDefaults保存形式 `@{ @"keyCode": ..., @"modifiers": ... }`
  - デフォルト:
    - メイン: Cmd+Shift+V
    - 履歴: Cmd+Ctrl+V
    - スニペット: Cmd+Shift+B
    - 履歴クリア: 未設定
- `src/Revclip/Revclip/App/RCAppDelegate.m` を更新:
  - `RCHotKeyService` を初期化
  - `RCEnvironment.hotKeyService` に登録
  - 起動時 `loadAndRegisterHotKeysFromDefaults` 実行
  - 終了時 `unregisterAllHotKeys` 実行
- `src/Revclip/Revclip/Managers/RCMenuManager.m` を更新:
  - ホットキー通知4種の監視を追加
  - メイン通知で通常ステータスメニューをポップアップ
  - 履歴通知で履歴専用メニューをポップアップ
  - スニペット通知でスニペット専用メニューをポップアップ
  - 一時メニュー表示後に元の`statusItem.menu`へ復元
  - 履歴クリア通知で `clearHistoryMenuItemSelected:` を実行
- `src/Revclip/project.yml` を更新:
  - `Carbon.framework` を target dependencies に追加
- `cd src/Revclip && xcodegen generate` を実行

## 検証結果
- `xcodegen generate`: 成功
- 構文チェック（PASS）:
  - `xcrun clang -fobjc-arc -fsyntax-only ... Revclip/Services/RCHotKeyService.m`
  - `xcrun clang -fobjc-arc -fsyntax-only ... Revclip/Managers/RCMenuManager.m`
  - `xcrun clang -fobjc-arc -fsyntax-only ... Revclip/App/RCAppDelegate.m`
- 全体ビルド:
  - `xcodebuild` は実行不可（この環境の `xcode-select` が Command Line Tools を指しており、フルXcodeが未選択）

## 例外・省略
- Worktree作成は省略: ユーザーから「メインブランチで作業してOK」の明示許可あり。
- Blueprint/TDDは省略: 既存構成へのサービス追加と起動配線を優先し、構文チェックで妥当性を確認。

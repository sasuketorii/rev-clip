# ExecPlan: Task 2-3 Preferences Window Controller

## 背景
Clipy同等のタブ式Preferencesウィンドウ基盤を導入し、今後のTask 2-3a〜2-3gで各タブ実装を積み上げるための土台を作る。

## スコープ
- `RCPreferencesWindowController`（`NSWindowController` + `NSToolbar`）新規実装
- 7タブ分のプレースホルダー `NSViewController` + 手書きXIBを追加
- PreferencesウィンドウXIBを追加
- `RCAppDelegate` に `showPreferencesWindow:` / `showPreferences:` を追加
- `project.yml` の取り込み範囲確認

## 実装ステップ
1. Preferences用Controller/ViewControllerクラス骨格を追加
2. 7タブ切替・lazyロード・ウィンドウリサイズアニメーションを実装
3. 手書きXIB（Window + 7タブ）を追加
4. `RCAppDelegate` 連携を追加
5. `xcodegen generate` と構文チェック、SOW記録

## 検証
- `cd src/Revclip && xcodegen generate`
- `xcrun clang -fobjc-arc -fsyntax-only -fmodules -IRevclip -IRevclip/Vendor Revclip/App/RCAppDelegate.m`
- `xcrun clang -fobjc-arc -fsyntax-only -fmodules -IRevclip -IRevclip/Vendor Revclip/UI/Preferences/RCPreferencesWindowController.m`

## 省略方針
- Worktree作成は省略: ユーザーから「メインブランチで直接作業可」の明示許可あり。
- Blueprint/TDDは省略: 今回はUI基盤追加タスクで、ユーザー指定でテストはPhase 3で一括実施。

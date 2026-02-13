# ExecPlan: Task 2-4 Snippet Editor Window

## 背景
Clipy同等のスニペット編集UIを追加し、フォルダ/スニペット管理（CRUD・並べ替え）とフォルダ個別ホットキー設定を一元化する。

## スコープ
- `RCSnippetEditorWindowController`（singleton `NSWindowController`）新規実装
- `RCSnippetEditorWindow.xib` 新規追加
- `NSOutlineView` 2階層（フォルダ/スニペット）+ D&D並べ替え
- 右ペイン編集（Title / Content / Shortcut recorder）
- `RCDatabaseManager` 既存API確認と不足API追加（`insertSnippet:inFolder:` / `updateSnippet:` / `updateSnippetFolder:`）
- `RCAppDelegate` に `showSnippetEditor:` を追加
- `RCMenuManager` に `Edit Snippets...` 導線を追加

## 実装ステップ
1. `RCDatabaseManager.h/.m` に不足APIを追加し、既存 `...withDict:` APIと共存させる
2. `UI/SnippetEditor/` を作成し `RCSnippetEditorWindowController.h/.m` を実装
3. `RCSnippetEditorWindow.xib` を手書き追加
4. `RCAppDelegate.m` / `RCMenuManager.m` に表示導線を追加
5. `xcodegen generate`・構文チェック・XIB XML検証・SOW記録

## 検証
- `cd src/Revclip && xcodegen generate`
- `xcrun clang -fobjc-arc -fsyntax-only -fmodules -IRevclip -IRevclip/App -IRevclip/Managers -IRevclip/Services -IRevclip/UI/HotKeyRecorder -IRevclip/UI/SnippetEditor Revclip/App/RCAppDelegate.m`
- `xcrun clang -fobjc-arc -fsyntax-only -fmodules -IRevclip -IRevclip/App -IRevclip/Managers -IRevclip/Services -IRevclip/UI/HotKeyRecorder -IRevclip/UI/SnippetEditor Revclip/Managers/RCMenuManager.m`
- `xcrun clang -fobjc-arc -fsyntax-only -fmodules -IRevclip -IRevclip/App -IRevclip/Managers -IRevclip/Services -IRevclip/UI/HotKeyRecorder -IRevclip/UI/SnippetEditor Revclip/UI/SnippetEditor/RCSnippetEditorWindowController.m`
- `xmllint --noout Revclip/UI/SnippetEditor/RCSnippetEditorWindow.xib`

## 省略方針
- Worktree作成は省略: ユーザーから「メインブランチで作業してOK」の明示許可あり。
- Blueprint/TDDは省略: ユーザー制約でテスト不要、UI/統合作業を優先し構文検証で担保。

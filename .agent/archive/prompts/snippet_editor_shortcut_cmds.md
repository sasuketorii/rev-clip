# タスク: スニペットエディタ UI改修（ショートカット削除 + Cmd+S保存）

## AGENT_ROLE=coder

## 許可事項
ユーザーからの明示的許可: メインブランチで作業してOKです。Worktree/ブランチを切る必要はありません。

## 対象ファイル
- `src/Revclip/Revclip/UI/SnippetEditor/RCSnippetEditorWindowController.m`
- `src/Revclip/Revclip/UI/SnippetEditor/RCSnippetEditorWindowController.h`（必要に応じて）

## 変更内容

### 1. ショートカットUI の完全削除

スニペットエディタの右ペイン下部にある「ショートカット: クリックして記録」UIを完全に削除する。

**削除対象:**
- `self.shortcutContainer` ビューとその中身（ショートカットラベル + `self.hotKeyRecorderView`）
- shortcutContainer の作成コード（`buildInterfaceIfNeeded` 内、おそらく行294〜336付近）
- shortcutContainer の Auto Layout 制約
- shortcutContainer の表示/非表示ロジック（`updateEditorForSelection` 等で `shortcutContainer.hidden = ...` を設定している箇所）
- `self.hotKeyRecorderView` のデリゲートメソッド呼び出し等、shortcutContainer に関連するUI更新コード

**削除しないもの（重要）:**
- `RCHotKeyRecorderView` クラス自体（他で使用されている可能性がある）
- `RCHotKeyService` のビジネスロジック
- ヘッダーファイルの `@property` 宣言のうち、hotKeyRecorderView や shortcutContainer がある場合は削除してよい

### 2. Cmd+S (⌘S) で保存機能の追加

ウィンドウコントローラーに `performKeyEquivalent:` をオーバーライドして、⌘S で `saveButtonClicked:` を呼び出す。

```objc
// RCSnippetEditorWindowController に追加（またはウィンドウのサブクラスで）
// ⌘S を検出して保存を実行
```

**実装方針:**
- `performKeyEquivalent:` は NSResponder のメソッド。NSWindowController のサブクラスではなく、ウィンドウの contentView やウィンドウ自体でオーバーライドする必要があるかもしれない。
- 最も確実な方法: ウィンドウコントローラーの `windowDidLoad` や `buildInterfaceIfNeeded` で NSMenuItem ベースのキーエクイバレントを設定するか、ウィンドウのデリゲートで `keyDown:` を処理する。
- **推奨アプローチ**: ウィンドウに対してローカルの NSEvent モニター (`addLocalMonitorForEventsMatchingMask:handler:`) を使うか、カスタム NSWindow サブクラスで `performKeyEquivalent:` をオーバーライドする。
- あるいは、最もシンプルな方法として、saveButton に `keyEquivalent` を設定する:
  ```objc
  self.saveButton.keyEquivalent = @"s";
  self.saveButton.keyEquivalentModifierMask = NSEventModifierFlagCommand;
  ```
  ← これが最もシンプルで確実。この方法を推奨。

### 3. 「⌘Sで保存」ラベルの追加

内容テキストビュー（`self.contentScrollView`）の下に、小さな灰色のテキストで「⌘Sで保存」と表示する。

**仕様:**
- フォントサイズ: 11pt（小さめ）
- 色: `NSColor.secondaryLabelColor`（灰色系）
- 位置: 内容テキストビューの下、左寄せ
- テキスト: ローカライズ対応で `NSLocalizedString(@"Save with ⌘S", nil)` → 日本語: 「⌘Sで保存」
- ショートカットコンテナを削除した分のスペースをここに使う

**レイアウト:**
- shortcutContainer を削除した後、contentScrollView の bottomAnchor の制約を調整
- 新しい小さなラベルを contentScrollView の下に配置
- ラベルの下はペインの底に適切なマージンで接続

### 4. ローカライズ

以下のローカライズファイルに新しい文字列を追加:
- `en.lproj/Localizable.strings`: `"Save with ⌘S" = "Save with ⌘S";`
- `ja.lproj/Localizable.strings`: `"Save with ⌘S" = "⌘Sで保存";`

他の言語ファイル（de, zh-Hans, it）にもあれば追加。

## 制約
- `self.saveButton` が `nil` でないか、選択項目があるかのチェックを忘れずに
- 既存のテスト（あれば）を壊さないこと
- ARCが有効なので `retain`/`release` は不要

# レビュー依頼: スニペットエディタ UI改修（ショートカット削除 + Cmd+S保存）

## AGENT_ROLE=reviewer

## 変更概要
スニペットエディタから「ショートカット: クリックして記録」UIを削除し、Cmd+S(⌘S)での保存機能と「⌘Sで保存」ヒントラベルを追加した。

## 変更ファイル
- `src/Revclip/Revclip/UI/SnippetEditor/RCSnippetEditorWindowController.m` (メイン変更)
- `src/Revclip/Revclip/Resources/*/Localizable.strings` (ローカライズ追加)

## 変更内容
1. **ショートカットUI削除**: `shortcutContainer`, `hotKeyRecorderView`, `RCHotKeyRecorderViewDelegate` 関連コードを削除（-208行）
2. **⌘S保存**: `saveButton.keyEquivalent = @"s"` + `performKeyEquivalent:` オーバーライド
3. **ヒントラベル**: 「⌘Sで保存」ラベルを内容テキストビュー下に追加（11pt, secondaryLabelColor）
4. **ローカライズ**: 5言語に `"Save with ⌘S"` を追加

## レビュー観点
1. ショートカットUIの削除が完全か（参照漏れがないか）
2. ⌘S保存の実装が正しいか（keyEquivalent + performKeyEquivalent の二重実装は適切か）
3. ヒントラベルのレイアウト制約が正しいか
4. 既存の保存ロジック（saveButtonClicked:）への影響がないか
5. Auto Layout 制約の整合性（shortcutContainer削除後の制約再構成）
6. ローカライズ文字列が正しいか

## レビューのフォーマット
- 問題がなければ「LGTM」と明記してください
- 問題があれば具体的な修正箇所と修正内容を指示してください

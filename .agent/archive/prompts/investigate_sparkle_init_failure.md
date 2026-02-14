# 調査依頼: Sparkle アップデート機能の初期化失敗

## AGENT_ROLE=coder (調査 + 修正)

## 許可事項
ユーザーからの明示的許可: メインブランチで作業してOKです。Worktree/ブランチを切る必要はありません。

## 問題
v0.0.11にアップデート後、設定 > アップデートタブで「今すぐ確認」をクリックすると:
- ダイアログ: 「アップデートの確認に失敗しました」
- メッセージ: 「アップデート機能の初期化に失敗しました。しばらくしてからもう一度お試しください。」

## 背景
- Sparkle 2.6.4 を使用
- `SUFeedURL` = `https://github.com/sasuketorii/rev-clip/releases/latest/download/appcast.xml`
- `SUPublicEDKey` = `jW5CH5/B8IApRFYiwOGot/VUmo0uqvE1LawgUG1igUk=`
- v0.0.10 → v0.0.11 の変更で、スニペットエディタのショートカット関連コードを削除した
- **重要**: v0.0.11で `RCHotKeyRecorderViewDelegate` をウィンドウコントローラーから削除した

## 調査観点
1. **エラーメッセージの出所を特定**: 「アップデート機能の初期化に失敗しました」がどこで生成されているか
   - ローカライズファイルで `"Update initialization failed"` 等を検索
   - Sparkle の SPUUpdater 初期化コードを確認
2. **Sparkle 初期化フロー**: SPUUpdater / SPUStandardUpdaterController がどこで初期化されているか
   - `RCUpdateManager` や `RCPreferencesUpdateViewController` を確認
3. **v0.0.11 での変更の影響**: ショートカット削除がSparkle初期化に影響していないか確認
4. **Sparkle.framework の存在確認**: ビルド成果物に Sparkle.framework が正しく含まれているか
5. **Info.plist の SUFeedURL / SUPublicEDKey が正しいか**

## 修正
根本原因を特定したら、修正コードを実装してください。

## 対象ファイル（調査対象）
- `src/Revclip/Revclip/` 配下の Sparkle 関連ファイル全般
- `src/Revclip/Revclip/Resources/*/Localizable.strings` （エラーメッセージの出所）
- `src/Revclip/Revclip/Info.plist`
- `src/Revclip/Revclip/UI/SnippetEditor/RCSnippetEditorWindowController.m` （v0.0.11変更）

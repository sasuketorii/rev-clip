# ExecPlan: Snippet Editor 有効/無効トグル追加

## 背景
スニペットエディタで選択中のフォルダ/スニペットを有効・無効切替できるUIが不足している。

## スコープ
- `RCSnippetEditorWindowController.m` に有効/無効トグルボタンを追加
- OutlineView の無効項目をグレーアウト
- 切替時に DB 更新とメニュー再構築を実施
- 既存実装確認の上、必要ならメニュー側/永続化側の追補

## 実行手順
1. 既存のボトムバー配置に「有効/無効」ボタンを追加（削除の右隣）
2. 選択状態に応じて eye / eye.slash を切替表示
3. トグルアクションで folder/snippet の `enabled` を反転して保存
4. OutlineView 描画で disabled 項目のテキスト色を `secondaryLabelColor` に変更
5. ビルド実行でコンパイル確認

## 検証
- `xcodebuild -project src/Revclip/Revclip.xcodeproj -scheme Revclip -configuration Debug -sdk macosx build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`

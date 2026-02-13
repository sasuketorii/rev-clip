# SOW: Task 2-2 ホットキーレコーダーUI

## 概要
- `RCHotKeyRecorderView` を新規実装し、KeyComboの記録・表示・クリアを提供。
- 録音モード時の視覚フィードバック（枠線色変更）と、`⌘⇧V` 形式の表示を実装。
- `keyDown:` / `flagsChanged:` でキーコード・修飾キー取得を実装。
- Option単独 / Option+Shift系の組み合わせ時に警告アラートを表示。
- `xcodegen generate` を実行し、Xcodeプロジェクトへ新規UIファイルを反映。

## 実施内容
- `src/Revclip/Revclip/UI/HotKeyRecorder/RCHotKeyRecorderView.h` を新規追加:
  - `RCHotKeyRecorderViewDelegate` 定義
  - `keyCombo` / `isRecording` / `startRecording` / `stopRecording` / `clearKeyCombo`
- `src/Revclip/Revclip/UI/HotKeyRecorder/RCHotKeyRecorderView.m` を新規追加:
  - クリックで録音開始、`ESC` でキャンセル、`Delete` でクリア
  - `flagsChanged:` で修飾キーのリアルタイム表示更新
  - `UCKeyTranslate` + 特殊キー定数テーブルによるキーコード文字列化
  - 修飾キーシンボル（`⌘⇧⌃⌥`）の整形
  - Option単独 / Option+Shift系（Cmd/Ctrlなし）検出時の警告表示
  - `drawRect:` で角丸枠・背景・中央テキスト描画
- `cd src/Revclip && xcodegen generate` を実行

## 検証結果
- `xcodegen generate`: 成功
- 構文チェック（PASS）:
  - `xcrun clang -fobjc-arc -fsyntax-only ... Revclip/UI/HotKeyRecorder/RCHotKeyRecorderView.m`
- 全体ビルド:
  - `xcodebuild` は実行不可（`xcode-select` が Command Line Tools を指しており、フルXcode未選択）

## 例外・省略
- Worktree作成は省略: ユーザーから「メインブランチで作業してOK」の明示許可あり。
- Blueprint/TDDは省略: 既存UI群への単機能追加を優先し、構文チェックで妥当性を確認。

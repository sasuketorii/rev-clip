# SOW: Task 1-9 UserDefaults初期化 + ユーティリティ

## 概要
- `RCUtilities` を新規実装し、指定された全デフォルト設定を `registerDefaults:` で登録。
- Utilityカテゴリとして `NSColor+HexString`、`NSImage+Resize`、`NSImage+Color` を Objective-C で追加。
- `Utilities` グループ/ソースを Xcode プロジェクトに反映。

## 実施内容
- `src/Revclip/Revclip/Utilities/RCUtilities.h/.m` を追加:
  - `+registerDefaultSettings` 実装（指定されたキー・デフォルト値を全登録）
  - `+applicationSupportPath` 実装
  - `+clipDataDirectoryPath` 実装
  - `+ensureDirectoryExists:` 実装
- `src/Revclip/Revclip/Utilities/NSColor+HexString.h/.m` を追加:
  - `+colorWithHexString:`（`#RGB/#RGBA/#RRGGBB/#RRGGBBAA` 対応）
  - `-hexString`（不透明時 `#RRGGBB`、透過あり時 `#RRGGBBAA`）
  - `+isValidHexColorString:`
- `src/Revclip/Revclip/Utilities/NSImage+Resize.h/.m` を追加:
  - `-resizedImageToSize:`
  - `-resizedImageToFitSize:`（アスペクト比維持、拡大は行わない）
- `src/Revclip/Revclip/Utilities/NSImage+Color.h/.m` を追加:
  - `+imageWithColor:size:`
  - `+imageWithColor:size:cornerRadius:`
- `xcodegen generate` を実行し、`src/Revclip/Revclip.xcodeproj/project.pbxproj` を更新:
  - `Utilities` グループ作成
  - 追加した `.m` ファイルを target Sources に追加

## 検証結果
- `xcodegen generate`: 成功（project再生成完了）
- 構文チェック（PASS）:
  - `xcrun clang -fsyntax-only ... Revclip/Utilities/RCUtilities.m`
  - `xcrun clang -fsyntax-only ... Revclip/Utilities/NSColor+HexString.m`
  - `xcrun clang -fsyntax-only ... Revclip/Utilities/NSImage+Resize.m`
  - `xcrun clang -fsyntax-only ... Revclip/Utilities/NSImage+Color.m`

## 例外・省略
- Worktree作成は省略: ユーザーから「メインブランチで作業してOK」の明示許可あり。
- Blueprint/TDDは省略: 既存設計に沿ったユーティリティ実装であり、まず実装と構文検証を優先。

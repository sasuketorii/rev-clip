# SOW: Task 2-7 データクリーンアップサービス

## 概要
- `RCDataCleanService` を新規実装し、30分間隔タイマーによる定期クリーンアップを追加。
- 履歴上限超過分のDBレコード削除と、対応するデータ/サムネイルファイル削除を実装。
- クリップ保存ディレクトリ内の孤立 `.rcclip` ファイル削除を実装。
- `RCAppDelegate` に統合し、起動時開始・終了時停止を追加。

## 実施内容
- `src/Revclip/Revclip/Services/RCDataCleanService.h/.m` を追加:
  - `+shared`
  - `-startCleanupTimer` / `-stopCleanupTimer`
  - `-performCleanup`
  - バックグラウンドシリアルキュー上で以下を実行:
    - 上限超過時: `clipItemCount` と `kRCPrefMaxHistorySizeKey` を比較し、古い順（`fetchClipItemsWithLimit:count` の後半）を削除
    - 削除時: DB削除成功後に `dataPath` / `thumbnailPath` / 互換サムネイル（`.thumb`, `.thumbnail.tiff`）を削除
    - 孤立ファイル削除: `clipDataDirectoryPath` 配下の `.rcclip` を列挙し、DBに存在しないパスを削除
- `src/Revclip/Revclip/App/RCAppDelegate.m` を更新:
  - 起動時に `RCDataCleanService` を `RCEnvironment` に設定
  - `startCleanupTimer` を起動フローに追加
  - 終了時に `stopCleanupTimer` を追加
- `cd src/Revclip && xcodegen generate` を実行し、`project.pbxproj` を再生成

## 検証結果
- `xcodegen generate`: 成功
- 構文チェック（PASS）:
  - `xcrun clang -fsyntax-only ... Revclip/Services/RCDataCleanService.m`
  - `xcrun clang -fsyntax-only ... Revclip/App/RCAppDelegate.m`
- `xcodebuild` は環境制約で未実行:
  - Active developer directory が CommandLineTools のため、Xcode本体未選択エラー

## 例外・省略
- Worktree作成は省略: ユーザーから「メインブランチで作業してOK」の明示許可あり。
- Blueprint/TDDは省略: 既存サービス構成への追加実装タスクであり、既存方針に沿って実装と構文検証を優先。

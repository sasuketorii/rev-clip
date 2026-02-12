# SOW: Task 1-5 クリップボード監視サービス

## 概要
- `RCClipboardService` を新規実装し、`NSPasteboard.changeCount` のポーリング監視と履歴保存フローを追加。
- 重複クリップ処理、保存タイプフィルタ、画像サムネイル生成、履歴上限超過時の古いデータ削除、通知配信を実装。

## 実施内容
- `src/Revclip/Revclip/Services/RCClipboardService.h` を追加:
  - `+shared`
  - `-startMonitoring` / `-stopMonitoring`
  - `@property (readonly) isMonitoring`
  - `-captureCurrentClipboard`
  - `RCClipboardDidChangeNotification` 定義
- `src/Revclip/Revclip/Services/RCClipboardService.m` を追加:
  - `dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, ...)` で 0.5秒ポーリング
  - `changeCount` 比較による変更検知
  - `RCClipData` 生成 → `dataHash` 算出 → DB重複判定
  - `kRCPrefOverwriteSameHistory` / `kRCPrefReorderClipsAfterPasting` による既存行の `update_time` 更新
  - 新規時の `.rcclip` ファイル保存 + DB INSERT
  - `kRCPrefStoreTypesKey` による保存タイプフィルタ
  - TIFF画像のサムネイル生成（`kRCThumbnailWidthKey` / `kRCThumbnailHeightKey`）
  - HEXカラー文字列判定（`NSColor+HexString`）で `is_color_code` 設定
  - `kRCPrefMaxHistorySizeKey` 超過時に古い履歴と対応ファイルを削除
  - `RCClipboardDidChangeNotification` をメインスレッドで送出（`userInfo[@"clipItem"]`）
  - ポーリングはバックグラウンドシリアルキュー、ファイル操作は別シリアルキューで実行
- `xcodegen generate` を実行し、`src/Revclip/Revclip.xcodeproj/project.pbxproj` を再生成。

## 検証結果
- `xcodegen generate`: 成功
- 構文チェック（PASS）:
  - `cd src/Revclip && xcrun clang -fobjc-arc -fsyntax-only -x objective-c -IRevclip/App -IRevclip/Managers -IRevclip/Models -IRevclip/Utilities -IRevclip/Services -IRevclip/Vendor/FMDB Revclip/Services/RCClipboardService.m`

## 例外・省略
- Worktree作成は省略: ユーザーから「メインブランチで作業してOK」の明示許可あり。
- Blueprint/TDDは省略: 既存アーキテクチャに沿った単一サービス追加を優先し、先に実装＋構文検証を実施。

# SOW: Task 2-6 除外アプリ add/remove の排他制御

## 概要
- `RCExcludeAppService` の除外アプリ一覧操作における read-modify-write の競合リスクを解消。
- `@synchronized(self)` により `excludedBundleIdentifiers` / `setExcludedBundleIdentifiers` / `addExcludedBundleIdentifier:` / `removeExcludedBundleIdentifier:` を直列化。

## 実施内容
- `src/Revclip/Revclip/Services/RCExcludeAppService.m` を更新:
  - `excludedBundleIdentifiers` を `@synchronized(self)` で保護し、読み取りとサニタイズ処理を排他化。
  - `setExcludedBundleIdentifiers` を `@synchronized(self)` で保護し、書き込みを排他化。
  - `addExcludedBundleIdentifier:` を `@synchronized(self)` で保護し、存在確認から追加保存までを単一クリティカルセクション化。
  - `removeExcludedBundleIdentifier:` を `@synchronized(self)` で保護し、読み取りから削除保存までを単一クリティカルセクション化。

## 検証結果
- 構文チェック（PASS）:
  - `xcrun --sdk macosx clang -fobjc-arc -fsyntax-only -fmodules -isysroot "$(xcrun --sdk macosx --show-sdk-path)" -I src/Revclip/Revclip -I src/Revclip/Revclip/App src/Revclip/Revclip/Services/RCExcludeAppService.m`

## 例外・省略
- Worktree作成は省略: ユーザーから「メインブランチで作業OK」の明示許可あり。
- Blueprint/TDDは省略: 既存サービス内のスレッド安全性を改善する局所修正であり、実装後に構文検証を実施。

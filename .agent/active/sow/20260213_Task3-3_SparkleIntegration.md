# SOW: Task 3-3 Sparkle 2.x Integration

## 概要
- Sparkle 2.x フレームワークを `Vendor/Sparkle` に配置し、Revclip で埋め込み可能なプロジェクト設定を追加。
- `RCUpdateService` を新規実装し、Sparkle の動的ロード（`NSBundle bundleWithPath:`）と graceful degradation を実装。
- `project.yml` の settings に Sparkle 用情報（`SUFeedURL` / `SUPublicEDKey`）を追加。

## 実施内容
- Sparkle取得:
  - `https://github.com/nicklama/Sparkle/releases/download/2.7.6/Sparkle-2.7.6.tar.xz` は取得不可
  - フォールバックで `https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz` を取得成功
  - `src/Revclip/Revclip/Vendor/Sparkle/Sparkle.framework` に配置
- `src/Revclip/Revclip/Services/RCUpdateService.h/.m` を新規追加:
  - singleton (`shared`)
  - `setupUpdater` / `checkForUpdates` API
  - Sparkle.framework の候補パス探索 + `loadAndReturnError:` による動的ロード
  - `SPUStandardUpdaterController` をランタイムで初期化
  - `automaticallyChecksForUpdates` / `updateCheckInterval` を `NSUserDefaults` (`kRCEnableAutomaticCheckKey`, `kRCUpdateCheckIntervalKey`) にバインド
  - Sparkle未存在時は no-op（graceful degradation）
- `src/Revclip/project.yml` を更新:
  - `dependencies` に `Revclip/Vendor/Sparkle/Sparkle.framework`（`embed: true`）追加
  - `FRAMEWORK_SEARCH_PATHS` に `$(PROJECT_DIR)/Revclip/Vendor/Sparkle` 追加
  - `SUFeedURL` / `SUPublicEDKey` を settings に追加
- `cd src/Revclip && xcodegen generate` 実行により `Revclip.xcodeproj/project.pbxproj` を再生成

## 検証結果
- `xcodegen generate`: 成功
- `xcrun clang -fobjc-arc -fsyntax-only -fmodules -IRevclip -IRevclip/App -IRevclip/Services Revclip/Services/RCUpdateService.m`: 成功

## 例外・省略
- Worktree作成は省略: ユーザーからメインブランチ作業許可あり。
- Blueprint/TDDは省略: ユーザー要件で「テスト不要」が明示されているため、生成と構文検証で確認した。
- Sparkle 2.7.6 は取得できなかったため 2.6.4 を採用（フレームワーク取得自体は成功したためスタブ運用には移行せず）。

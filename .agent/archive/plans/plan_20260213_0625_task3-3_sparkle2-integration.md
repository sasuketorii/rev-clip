# ExecPlan: Task 3-3 Sparkle 2.x Integration

## 背景
Revclip に Sparkle 2.x を組み込み、自動アップデート機能の土台（更新チェック設定・手動チェックAPI・Info.plist連携）を実装する。

## スコープ
- `src/Revclip/Revclip/Vendor/Sparkle/` へ `Sparkle.framework` の配置（取得成功時）
- `src/Revclip/Revclip/Services/RCUpdateService.h/.m` 新規追加
- `src/Revclip/project.yml` へ Sparkle 用設定（`SUFeedURL` / `SUPublicEDKey`）追加
- 取得成功時のみ `project.yml` に Sparkle.framework の依存・埋め込みを追加
- `AppDelegate` は変更しない

## 実装ステップ
1. Sparkle 2.x の取得を試行し、成功/失敗を判定する
2. `RCUpdateService` を新規作成し、動的ロード + graceful degradation を実装する
3. `project.yml` の Info.plist設定と framework 設定を更新する（失敗時は framework 追加をスキップ）
4. `xcodegen generate` で生成確認し、構文/設定整合を検証する
5. SOW を記録する

## 検証
- `cd src/Revclip && xcodegen generate`
- （必要に応じて）`rg` による設定反映確認

## 省略方針
- Worktree作成は省略: ユーザーから「メインブランチで作業OK。Worktree不要。」の明示許可あり。
- Blueprint/TDDは省略: ユーザー制約で「テスト不要」が明示されているため、生成・構文整合で担保する。

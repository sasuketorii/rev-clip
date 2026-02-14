# レビュー依頼: Sparkle アップデート確認エラーの修正

## AGENT_ROLE=reviewer

## 変更概要
v0.0.11で「今すぐ確認」をクリックすると「アップデート機能の初期化に失敗しました」と表示される問題を修正。

## 根本原因
`RCUpdateService.m` の `didFinishUpdateCycleForUpdateCheck:error:` デリゲートメソッドが、Sparkle の `SUNoUpdateError (code 1001)` を致命エラーとして扱い、失敗通知を発行していた。Sparkle の仕様上、「最新版で更新なし」は `SUNoUpdateError` として正常に返される。

## 修正内容
`RCUpdateService.m` に以下を追加:
1. `SUSparkleErrorDomain` 定数と `RCSparkleErrorCode` enum を追加
2. `didFinishUpdateCycleForUpdateCheck:error:` に `isIgnorableSparkleError:` チェックを追加
3. `isIgnorableSparkleError:` メソッドを新規追加（SUNoUpdateError=1001、SUInstallationCanceledError=4007 を非致命扱い）

## 変更ファイル
- `src/Revclip/Revclip/Services/RCUpdateService.m` (+32行)

## レビュー観点
1. `SUNoUpdateError (1001)` を非致命扱いにする判断は正しいか
2. `SUInstallationCanceledError (4007)` も非致命扱いにする判断は正しいか
3. `SUSparkleErrorDomain` のハードコード文字列が正しいか（Sparkle 2.x の実際のドメイン名と一致するか）
4. error が nil のケースのハンドリング
5. 既存のエラー通知フロー（reportFailureWithError:reason:）への影響がないか

## レビューのフォーマット
- 問題がなければ「LGTM」と明記してください

# AGENT_ROLE=coder

## 許可事項
ユーザーからの明示的許可: メインブランチで作業してOKです。Worktree/ブランチを切る必要はありません。現在のブランチで直接作業してください。

## タスク: レビュー指摘4件の修正

前回の修正に対するレビューで4件の指摘が出ました。以下を修正してください。

---

## 指摘1 (medium): canCheckForUpdates 判定前に setupUpdater を呼ぶ

**問題:** `RCUpdatesPreferencesViewController.m` の `checkNowClicked:` で `canCheckForUpdates` を先にチェックしているが、`checkForUpdates` 内の `setupUpdater` 再試行経路が使われない。

**修正方針:** `canCheckForUpdates` の getter 内で `setupUpdater` を呼び、初期化を試みてから判定する。

### RCUpdateService.m を修正:

```objc
- (BOOL)canCheckForUpdates {
    [self setupUpdater];
    @synchronized (self) {
        return self.updaterController != nil;
    }
}
```

これにより、`checkNowClicked:` から `canCheckForUpdates` を呼んだ時点で初期化再試行が走る。

---

## 指摘2 (medium): Sparkle 本来の canCheckForUpdates を利用

**問題:** `canCheckForUpdates` が `updaterController != nil` のみ返しており、Sparkle の `SPUUpdater.canCheckForUpdates`（チェック中かどうか等）を反映していない。

**修正方針:** `RCSPUUpdater` プロトコルに `canCheckForUpdates` を追加し、Sparkle updater の状態も考慮する。

### RCUpdateService.m のプロトコル定義を修正:

```objc
@protocol RCSPUUpdater <NSObject>
@property (nonatomic, assign) BOOL automaticallyChecksForUpdates;
@property (nonatomic, assign) NSTimeInterval updateCheckInterval;
@optional
@property (nonatomic, readonly) BOOL canCheckForUpdates;
@end
```

### canCheckForUpdates の実装を修正:

```objc
- (BOOL)canCheckForUpdates {
    [self setupUpdater];
    @synchronized (self) {
        if (self.updaterController == nil) {
            return NO;
        }
        id<RCSPUUpdater> updater = [self currentUpdater];
        if (updater != nil && [updater respondsToSelector:@selector(canCheckForUpdates)]) {
            return updater.canCheckForUpdates;
        }
        return YES;
    }
}
```

---

## 指摘3 (medium): 3秒固定タイマーを Sparkle 状態監視に変更

**問題:** 3秒固定の `dispatch_after` でスピナーを止めているが、Sparkle の実際の完了と同期していない。

**修正方針:** KVO で `SPUUpdater.canCheckForUpdates` を監視する。ただし、Sparkle のプロトコルベースの設計に合わせ、以下のアプローチを採用する。

### RCUpdatesPreferencesViewController.m を修正:

`checkNowClicked:` でボタンを無効化し、ポーリングタイマーで Sparkle の `canCheckForUpdates` を監視する。

```objc
- (IBAction)checkNowClicked:(id)sender {
    (void)sender;

    RCUpdateService *updateService = [RCUpdateService shared];
    if (!updateService.canCheckForUpdates) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleWarning;
        alert.messageText = NSLocalizedString(@"アップデートを確認できません", nil);
        alert.informativeText = NSLocalizedString(@"アップデート機能の初期化に失敗しました。アプリケーションを再起動してください。", nil);
        [alert addButtonWithTitle:NSLocalizedString(@"OK", nil)];
        [alert runModal];
        return;
    }

    self.checkNowButton.enabled = NO;
    self.checkProgressIndicator.hidden = NO;
    [self.checkProgressIndicator startAnimation:nil];

    [updateService checkForUpdates];

    [self startCheckCompletionPolling];
}
```

ポーリングメソッド（0.5秒間隔、最大30秒タイムアウト）:

```objc
- (void)startCheckCompletionPolling {
    __block NSInteger pollCount = 0;
    __weak typeof(self) weakSelf = self;

    // Sparkle の canCheckForUpdates が YES に戻るまでポーリング（最大60回 = 30秒）
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), (uint64_t)(0.5 * NSEC_PER_SEC), (uint64_t)(0.1 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(timer, ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) {
            dispatch_source_cancel(timer);
            return;
        }

        pollCount++;
        BOOL canCheck = [RCUpdateService shared].canCheckForUpdates;
        if (canCheck || pollCount >= 60) {
            strongSelf.checkNowButton.enabled = YES;
            [strongSelf.checkProgressIndicator stopAnimation:nil];
            strongSelf.checkProgressIndicator.hidden = YES;
            dispatch_source_cancel(timer);
        }
    });
    dispatch_resume(timer);
}
```

**重要:** `__weak` を使って self のリテインサイクルを防ぐこと。

---

## 指摘4 (low): canCheckForUpdates のスレッドセーフ化

**問題:** `canCheckForUpdates` が `@synchronized` 外で `updaterController` を参照している。

**修正:** 指摘1・2の修正で `@synchronized (self)` 内に統合済み。

---

## 対象ファイル

1. `src/Revclip/Revclip/Services/RCUpdateService.m` — canCheckForUpdates改善、プロトコル拡張
2. `src/Revclip/Revclip/UI/Preferences/RCUpdatesPreferencesViewController.m` — ポーリング監視に変更

## 注意事項
- 既存のコードスタイルを維持
- プロトコル定義の変更は `RCSPUUpdater` の `@optional` セクションに追加
- `RCUpdateService.h` の `canCheckForUpdates` プロパティ宣言は変更不要
- ビルドが通ることを確認してください (`xcodebuild -project src/Revclip/Revclip.xcodeproj -scheme Revclip -configuration Debug -destination 'platform=macOS' build`)

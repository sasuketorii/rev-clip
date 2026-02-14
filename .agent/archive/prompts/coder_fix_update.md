# AGENT_ROLE=coder

## 許可事項
ユーザーからの明示的許可: メインブランチで作業してOKです。Worktree/ブランチを切る必要はありません。現在のブランチで直接作業してください。

## タスク: アップデート機能の修正

Revclip の Sparkle ベースのアップデート機能が壊れている。「今すぐ確認」ボタンを押しても何も起こらない（ポップアップもスピナーも出ない）。以下の根本原因を修正し、ユーザー目線のUXを実現せよ。

---

## 根本原因分析

### 原因1: SUPublicEDKey が空
**ファイル:** `src/Revclip/Revclip/Info.plist` (行39-40)
```xml
<key>SUPublicEDKey</key>
<string></string>
```
Sparkle 2.x は `SUPublicEDKey` が Info.plist に存在する場合、EdDSA 署名検証を要求する。空の値だと検証が必ず失敗し、アップデートチェックが動作しない。

**修正:** `SUPublicEDKey` キーとその値を Info.plist から完全に削除する。Apple Code Signing で検証するため EdDSA は不要。

### 原因2: didAttemptSetup フラグによる再試行不可
**ファイル:** `src/Revclip/Revclip/Services/RCUpdateService.m` (行52-75)
```objc
if (self.updaterController != nil || self.didAttemptSetup) {
    return;
}
self.didAttemptSetup = YES;
```
初回の `setupUpdater` が失敗した場合（Sparkle ロード失敗等）、`didAttemptSetup = YES` がセットされるが `updaterController` は nil のまま。以降の呼び出しは全てスキップされる。`checkForUpdates` は nil に対するメッセージ送信となり、何も起こらない。

**修正:** ガード条件を `self.updaterController != nil` のみに変更する。ただし無限ループ防止のため、一定時間（例: 30秒）はクールダウンを入れる。もしくは `didAttemptSetup` を成功時のみセットする。

### 原因3: ユーザーフィードバックが皆無
**ファイル:** `src/Revclip/Revclip/UI/Preferences/RCUpdatesPreferencesViewController.m` (行96-99)
```objc
- (IBAction)checkNowClicked:(id)sender {
    (void)sender;
    [[RCUpdateService shared] checkForUpdates];
}
```
ボタンクリック後、スピナーも、ステータスメッセージも、エラー表示もない。

### 原因4: 設定変更が Sparkle に伝達されていない
`automaticCheckToggled:` と `checkIntervalChanged:` は NSUserDefaults に保存するだけで、`RCUpdateService` のプロパティを更新していない。次回アプリ起動まで設定が反映されない。

---

## 修正指示

### 1. Info.plist から SUPublicEDKey を削除
**ファイル:** `src/Revclip/Revclip/Info.plist`

以下の2行を完全に削除:
```xml
<key>SUPublicEDKey</key>
<string></string>
```

### 2. RCUpdateService.m の修正

#### 2a. setupUpdater のガードを修正
`didAttemptSetup` フラグを削除し、`updaterController != nil` のみでガードする:
```objc
- (void)setupUpdater {
    @synchronized (self) {
        if (self.updaterController != nil) {
            return;
        }

        if (![self loadSparkleFrameworkIfAvailable]) {
            NSLog(@"[RCUpdateService] Sparkle.framework not found.");
            return;
        }

        Class updaterControllerClass = NSClassFromString(@"SPUStandardUpdaterController");
        if (updaterControllerClass == Nil) {
            NSLog(@"[RCUpdateService] SPUStandardUpdaterController class not found.");
            return;
        }

        self.updaterController = [self createUpdaterControllerWithClass:updaterControllerClass];
        if (self.updaterController == nil) {
            NSLog(@"[RCUpdateService] Failed to create updater controller.");
            return;
        }

        [self applyStoredPreferencesToUpdater];
        NSLog(@"[RCUpdateService] Sparkle updater initialized successfully.");
    }
}
```
`didAttemptSetup` プロパティも削除すること。

#### 2b. checkForUpdates にエラーハンドリングを追加
```objc
- (void)checkForUpdates {
    [self setupUpdater];
    if (self.updaterController == nil) {
        NSLog(@"[RCUpdateService] Cannot check for updates: updater not initialized.");
        return;
    }
    [self.updaterController checkForUpdates:nil];
}
```

#### 2c. canCheckForUpdates メソッドを追加（公開API）
ヘッダーに追加:
```objc
/// アップデートチェック可能かどうか
@property (nonatomic, readonly) BOOL canCheckForUpdates;
```
実装:
```objc
- (BOOL)canCheckForUpdates {
    return self.updaterController != nil;
}
```

### 3. RCUpdatesPreferencesViewController.m の修正

#### 3a. 設定変更を RCUpdateService に伝達
```objc
- (IBAction)automaticCheckToggled:(NSButton *)sender {
    BOOL automaticCheckEnabled = sender.state == NSControlStateValueOn;
    [RCUpdateService shared].automaticallyChecksForUpdates = automaticCheckEnabled;
    [self updateIntervalControlState];
}

- (IBAction)checkIntervalChanged:(NSPopUpButton *)sender {
    NSInteger intervalInSeconds = sender.selectedTag;
    if (intervalInSeconds <= 0) {
        intervalInSeconds = kRCDefaultUpdateCheckInterval;
        [sender selectItemWithTag:intervalInSeconds];
    }
    [RCUpdateService shared].updateCheckInterval = (NSTimeInterval)intervalInSeconds;
}
```
NSUserDefaults への直接保存は RCUpdateService 側で行うため、ViewController からの直接保存は不要。

#### 3b. checkNowClicked にフィードバックを追加
- ボタンをクリックしたら、ボタンを無効化する
- スピナー（NSProgressIndicator）を表示する
- Sparkle が結果を返した後（もしくは一定時間後）、ボタンを再有効化する
- updater が nil の場合、エラーアラートを表示する

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

    // ボタンを無効化してスピナーを表示
    self.checkNowButton.enabled = NO;
    [self.checkProgressIndicator startAnimation:nil];
    self.checkProgressIndicator.hidden = NO;

    [updateService checkForUpdates];

    // Sparkle が自身のUIを表示するため、一定時間後にボタンを再有効化
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.checkNowButton.enabled = YES;
        [self.checkProgressIndicator stopAnimation:nil];
        self.checkProgressIndicator.hidden = YES;
    });
}
```

#### 3c. 新しい IBOutlet を追加
```objc
@property (nonatomic, weak) IBOutlet NSButton *checkNowButton;
@property (nonatomic, weak) IBOutlet NSProgressIndicator *checkProgressIndicator;
```

### 4. RCUpdatesPreferencesView.xib の修正

#### 4a. 「今すぐ確認」ボタンに IBOutlet を接続
既存のボタン（ID: Qgg-fD-IJT）に `checkNowButton` outlet を追加。

#### 4b. NSProgressIndicator を追加
「今すぐ確認」ボタンの右隣に小さなスピナー（NSProgressIndicator, indeterminate spinning style, 16x16）を追加:
- Style: spinning
- Size: small (16x16)
- Hidden by default (hidden="YES")
- `checkProgressIndicator` outlet に接続

#### 4c. レイアウト調整
- スピナーは「今すぐ確認」ボタンの右側に 8pt のマージンで配置
- centerY をボタンに揃える

---

## 対象ファイル一覧

1. `src/Revclip/Revclip/Info.plist` — SUPublicEDKey 削除
2. `src/Revclip/Revclip/Services/RCUpdateService.h` — canCheckForUpdates プロパティ追加
3. `src/Revclip/Revclip/Services/RCUpdateService.m` — setupUpdater修正、canCheckForUpdates追加、didAttemptSetup削除
4. `src/Revclip/Revclip/UI/Preferences/RCUpdatesPreferencesViewController.m` — 設定伝達、フィードバック追加
5. `src/Revclip/Revclip/UI/Preferences/RCUpdatesPreferencesView.xib` — スピナー追加、outlet接続

## 注意事項
- Objective-C のコーディング規約を維持（既存コードスタイルに従う）
- NSLocalizedString を使用（日本語のデフォルト文字列を直接書いてOK）
- コメントは必要最低限
- 既存の Sparkle プロトコル定義（RCSPUUpdater, RCSPUStandardUpdaterController）は変更しない
- XIB の変更は手動編集で行うこと（Interface Builder 形式を維持）

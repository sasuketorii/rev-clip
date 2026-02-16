# SOW: Security & Data Hardening

**作成日**: 2026-02-16
**プラン参照**: `.agent/active/plan_20260216_security-and-data-hardening.md` (Rev.3, LGTM済み)
**現在のバージョン**: v0.0.15 (master branch, commit 9b1a907)

---

## 1. プロジェクト概要

### 1.1 対象アプリケーション
- **名称**: Revclip — macOS クリップボードマネージャー
- **言語**: Objective-C
- **フレームワーク**: Cocoa, FMDB (SQLite), Sparkle (auto-update), Carbon (HotKey)
- **動作環境**: macOS 14.0+, arm64 + x86_64
- **形態**: メニューバー常駐アプリ (LSUIElement: true)

### 1.2 目的
Codex xhigh 並列調査（5レーン: セキュリティ一般、データセキュリティ、データ成長、Auto-Expiry設計、Secure Wipe & Panic Button）の結果に基づき、以下を実現する:

1. **データ成長の制御** — クリップボードデータが無限に肥大化するリスクを排除
2. **Auto-Expiry機能** — 時間ベースの自動履歴削除（Day/Hour/Minute選択 + 数値入力）
3. **Panic Button** — 全履歴・テンプレートを跡形なく即時削除する緊急機能
4. **セキュリティ強化** — ファイルパーミッション、セキュア削除、XXE対策、パストラバーサル対策等

### 1.3 前提条件
- アプリは現在完璧に動作しており、バグ報告なし
- 既存動作を壊さないことが最優先
- ワンクリックアップデートで既存ユーザーに追加操作を要求しない
- 技術的限界（APFS/SSD上の物理的セキュア削除保証、at-rest暗号化等）はスコープ外

### 1.4 レビュー履歴
| ラウンド | Verdict | 指摘数 | 主な指摘 |
|---------|---------|--------|---------|
| Rev.1 | NEEDS_CHANGES | 10件 | TIFF互換性破壊、キュー排水不足、UI二重管理 等 |
| Rev.2 | NEEDS_CHANGES | 2件+2部分解決 | デッドロックリスク、非終了分岐未定義 |
| Rev.3 | **LGTM** | Low 1件のみ | `.thumb` レガシー拡張子もパーミッション修復対象に含める |

---

## 2. 成果物定義

### 2.1 Phase 1: Data Growth Control（データ成長制御）

| サブタスク | 成果物 | 受入基準 |
|-----------|--------|---------|
| 1-1. Per-item サイズ上限 | `RCConstants.h/m`, `RCUtilities.m`, `RCClipboardService.m`, `RCScreenshotMonitorService.m` の変更 | 50MB超のクリップが保存されないこと。os_logにdebugログが出力されること |
| 1-2. サムネイル圧縮 | `RCScreenshotMonitorService.m`, `RCClipboardService.m` の変更 | サムネイルがJPEG(quality 0.7)で保存されること。**画像本体TIFFDataは一切変更しない** |
| 1-3. 保存直後トリム | `RCClipboardService.m`, `RCScreenshotMonitorService.m`, `RCDataCleanService.h/m` の変更 | クリップ保存後5秒以内にトリムが実行されること。30分タイマーも維持 |
| 1-4. maxHistory clamp | `RCDataCleanService.m` の変更 | `defaults write`で極大値を設定しても1-9999にclampされること |
| 1-5. サムネイル寸法clamp | `RCClipboardService.m`, `RCScreenshotMonitorService.m`, `RCMenuManager.m` の変更 | サムネイル幅/高さが16-512にclampされること |

### 2.2 Phase 2: Auto-Expiry（自動期限切れ削除）

| サブタスク | 成果物 | 受入基準 |
|-----------|--------|---------|
| 2-1. Preference追加 | `RCConstants.h/m`, `RCUtilities.m` の変更 | 3キー（enabled/value/unit）が追加され、デフォルト値が登録されていること |
| 2-2. DBメソッド強化 | `RCDatabaseManager.h/m` の変更 | `clipItemsOlderThan:` が正しく期限切れアイテムを返すこと |
| 2-3. Expiryロジック | `RCDataCleanService.h/m` の変更 | cleanup順序が expiry→trim→orphan であること。サービス層でenabled/value/unitを検証すること |
| 2-4. UI実装 | `RCGeneralPreferencesViewController.h/m`, `RCGeneralPreferencesView.xib` の変更 | チェックボックス + 数値入力 + ステッパー + ポップアップが正しく連動すること。無効時はコントロールがdisabledであること |

### 2.3 Phase 3: Panic Button（緊急全削除）

| サブタスク | 成果物 | 受入基準 |
|-----------|--------|---------|
| 3-1. RCPanicEraseService | `RCPanicEraseService.h/m` **新規作成** | 12ステップのシーケンスが正しく実行されること。専用panicQueueで実行。書き込み禁止フラグが機能すること。最後にアプリ終了 |
| 3-2. DB close/reopen | `RCDatabaseManager.h/m` の変更 | close→delete→reinitialize が正しく動作すること |
| 3-3. Panicホットキー | `RCConstants.h/m`, `RCHotKeyService.h/m`, `RCMenuManager.m` の変更 | Cmd+Shift+Option+Delete でPanic実行。メニュー項目に確認ダイアログ付き |
| 3-4. Panic設定UI | `RCShortcutsPreferencesViewController.h/m`, `RCShortcutsPreferencesView.xib` の変更 | ホットキーカスタマイズがShortcuts画面に統合されていること |

### 2.4 Phase 4: Security Hardening（セキュリティ強化）

| サブタスク | 成果物 | 受入基準 |
|-----------|--------|---------|
| 4-1. パーミッション | `RCUtilities.h/m`, `RCClipData.m`, `RCDatabaseManager.m`, `RCAppDelegate.m` の変更 | ディレクトリ0700、ファイル0600が設定されること。起動時に既存ファイル（.rcclip, .thumbnail.tiff, .thumb）も修復されること |
| 4-2. secure_delete + VACUUM | `RCDatabaseManager.m`, `RCDataCleanService.m` の変更 | `PRAGMA secure_delete=ON`。既存DBのauto_vacuum移行が1回実行されること。30分cleanup時にincremental_vacuumが実行されること |
| 4-3. TM/Spotlight除外 | `RCUtilities.h/m`, `RCAppDelegate.m` の変更 | NSURLIsExcludedFromBackupKey=YES。.metadata_never_indexファイルが作成されること |
| 4-4. XXE対策 | `RCSnippetImportExportService.m` の変更 | NSXMLNodeLoadExternalEntitiesNeverが設定されること。DOCTYPE拒否。件数/長さ上限が適用されること |
| 4-5. パストラバーサル対策 | `RCClipData.m`, `RCDataCleanService.m` の変更 | ClipsData外パスが拒否されること |
| 4-6. os_log移行 | `RCClipData.m`, `RCDatabaseManager.m`, `RCClipboardService.m`, `RCDataCleanService.m` の変更 | 機密情報が`%{private}@`で保護されること |

### 2.5 Phase 5: Existing Deletion Enhancement（既存削除機能強化）

| サブタスク | 成果物 | 受入基準 |
|-----------|--------|---------|
| 5-1. Clear History強化 | `RCMenuManager.m` の変更 | ファイル削除前にbest-effort上書き。削除後にincremental_vacuum実行 |
| 5-2. DB定期メンテナンス | `RCDataCleanService.m` の変更 | 30分cleanup時にincremental_vacuum実行 |

---

## 3. 実装順序と依存関係

```
Phase 1 (Data Growth)  ──→  Phase 2 (Auto-Expiry)  ──→  Phase 3 (Panic Button)
                                                               │
Phase 4 (Security)  ────────────────────────────────────────────┘
                                                               │
Phase 5 (Deletion Enhancement)  ───────────────────────────────┘
```

### 依存関係
- Phase 1 と Phase 4 は**並列実装可能**（ファイル競合に注意: `RCDataCleanService.m`, `RCDatabaseManager.m` は両方で変更）
- Phase 2 は Phase 1-4（maxHistory clamp）に依存
- Phase 3 は Phase 4-2（secure_delete）に依存
- Phase 5 は Phase 3（best-effort上書きロジック共有）と Phase 4（secure_delete）に依存

### 並列実装時のコンフリクト注意ファイル
| ファイル | 競合するPhase | 対策 |
|---------|-------------|------|
| `RCConstants.h/m` | 1, 2, 3 | 順次実装（追記のみなのでコンフリクトリスク低） |
| `RCDataCleanService.m` | 1, 2, 4, 5 | **高リスク** — 順次実装推奨 |
| `RCDatabaseManager.m` | 2, 3, 4 | **高リスク** — 順次実装推奨 |
| `RCMenuManager.m` | 1, 3, 5 | 変更箇所が分散しているためリスク中程度 |

### 推奨実装順序（直列）
1. Phase 4（Security）— 基盤強化を先に
2. Phase 1（Data Growth）— 成長制御
3. Phase 2（Auto-Expiry）— 新機能
4. Phase 3（Panic Button）— 新機能（最も複雑）
5. Phase 5（Deletion Enhancement）— 最終仕上げ

---

## 4. 品質基準

### 4.1 テスト方針
各Phaseで以下を確認:
1. 既存機能が壊れていないこと（コピー→ペースト、履歴表示、スニペット管理）
2. 新機能が仕様通り動作すること
3. エッジケース（極大値、0値、不正入力、NSUserDefaults汚染）の処理
4. メモリリーク/クラッシュがないこと

### 4.2 レビュー体制
- 各Phase完了後にCodex xhigh（reviewer）でレビュー
- LGTM取得までcoder→reviewer反復
- 全Phase完了後に統合レビュー

### 4.3 既存ユーザー影響ゼロの保証
- DBスキーマ変更なし
- 新Preferenceは全て安全なデフォルト値
- Auto-Expiryはデフォルト無効
- Panic Buttonは誤爆しにくいキーコンボ
- auto_vacuum移行は初回起動時に透過的に実行（30件DBで0.03秒未満）

---

## 5. スコープ外（技術的限界）

以下は本SOWのスコープに含めない:
- APFS/SSD上での物理的セキュア削除の保証
- at-rest暗号化（SQLCipher/AES-GCM）
- cryptographic erase（暗号化前提のため）
- swap/VM/クラッシュレポート/Unified Logging の痕跡完全消去
- Time Machine既存バックアップの削除
- ARC環境でのメモリゼロ化保証

---

## 6. リスクと緩和策

| リスク | 影響度 | 緩和策 |
|-------|--------|-------|
| Phase 3 デッドロック | High | 専用panicQueue + dispatch_barrier_async + dispatch_sync禁止（Rev.3で対策済み） |
| auto_vacuum VACUUM 大容量DB | Medium | 移行フラグで1回限り + 失敗時はログのみで動作継続 |
| RCDataCleanService.m コンフリクト | Medium | 直列実装推奨。並列時はWorktree分離 |
| XIB変更の互換性 | Low | 新規要素追加のみ。既存要素は変更しない |

---

## 7. ディレクトリ・ファイル構成

### 7.1 プロジェクトルート
```
/Users/sasuketorii/dev/Revclip/
```

### 7.2 ソースコード
```
src/Revclip/Revclip/
├── App/
│   ├── RCAppDelegate.m          — 起動シーケンス
│   ├── RCConstants.h/m          — 定数・Preferenceキー
├── Managers/
│   ├── RCDatabaseManager.h/m    — SQLite操作（FMDB）
│   ├── RCMenuManager.m          — メニューバー管理
├── Models/
│   ├── RCClipData.h/m           — クリップデータモデル
│   ├── RCClipItem.h/m           — クリップメタデータ
├── Services/
│   ├── RCClipboardService.m     — クリップボード監視
│   ├── RCDataCleanService.h/m   — クリーンアップ
│   ├── RCScreenshotMonitorService.m — スクショ監視
│   ├── RCHotKeyService.h/m      — グローバルホットキー
│   ├── RCPasteService.m         — ペースト実行
│   ├── RCSnippetImportExportService.m — スニペットI/O
│   ├── RCPanicEraseService.h/m  — 【新規作成】Panic削除
├── UI/Preferences/
│   ├── RCGeneralPreferencesViewController.h/m
│   ├── RCGeneralPreferencesView.xib
│   ├── RCShortcutsPreferencesViewController.h/m
│   ├── RCShortcutsPreferencesView.xib
├── Utilities/
│   ├── RCUtilities.h/m          — ユーティリティ
```

### 7.3 エージェント関連
```
.agent/active/
├── plan_20260216_security-and-data-hardening.md  — ExecPlan (Rev.3, LGTM済み)
├── sow/20260216_security-and-data-hardening.md   — 本SOW
├── prompts/                                       — 調査・レビュー用プロンプト
```

### 7.4 データ保存先（ユーザー環境）
```
~/Library/Application Support/Revclip/
├── revclip.db                   — SQLiteデータベース
├── ClipsData/
│   ├── {UUID}.rcclip            — クリップデータ（NSKeyedArchiver）
│   ├── {UUID}.thumbnail.tiff    — サムネイル
│   └── {UUID}.thumb             — レガシーサムネイル
```

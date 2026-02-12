# SOW: Task 1-1 Project Setup

## 概要
- Revclip Objective-C プロジェクトの初期セットアップを `src/Revclip/` 配下に実施。
- `xcodegen generate` により `Revclip.xcodeproj` を生成。

## 実施内容
- ディレクトリ構成を作成（App/Services/Managers/Models/UI/Utilities/Vendor/Scripts/Distribution 等）。
- `project.yml` を作成（macOS 14.0, Bundle ID `com.revclip.Revclip`, ARC有効, Universal Binary, Hardened Runtime）。
- `main.m`, `Info.plist`, `Revclip.entitlements`, `Revclip-Prefix.pch`, `RCAppDelegate` を作成。
- `MainMenu.xib` を最小構成で作成（About/Quit, delegate 接続）。
- `Assets.xcassets` のプレースホルダー `Contents.json` 群を作成。
- `Makefile` を作成（setup/build/debug/release/test/clean/run/sign/notarize/dmg）。
- `Scripts/*.sh` スタブを作成し実行権限を付与。

## 検証結果
- `xcodegen generate` は成功。
- `Revclip.xcodeproj` が生成されたことを確認。

## 例外・省略
- Worktree作成は省略: ユーザーから「メインブランチで作業してOK」の明示許可あり。
- Blueprint/TDDは省略: 本タスクは初期ブートストラップ（構成・設定・最小スタブ作成）が主目的であり、機能実装フェーズではないため。

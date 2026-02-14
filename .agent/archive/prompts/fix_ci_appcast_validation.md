# タスク: CI ワークフローに appcast 署名バリデーションを追加

## 許可事項
ユーザーからの明示的許可: メインブランチで作業してOKです。Worktree/ブランチを切る必要はありません。

## バグ概要
Sparkle アップデート時に「署名が不適切で認証できません」エラーが発生。
根本原因は GitHub Secrets の SPARKLE_PRIVATE_KEY の値が不正だったこと（修正済み）。
しかし、CI ワークフローには appcast.xml に `sparkle:edSignature` が含まれているかの検証がなく、
署名なしの appcast がそのままリリースされてしまった。

## 対象ファイル
`.github/workflows/release.yml`

## 修正内容

### 1. "Generate appcast.xml" ステップの後に、バリデーションステップを追加

以下を "Generate appcast.xml" ステップと "Publish GitHub Release with assets" ステップの間に追加:

```yaml
      - name: Validate appcast.xml contains EdDSA signature
        run: |
          set -euo pipefail
          if [[ ! -f "${APPCAST_PATH}" ]]; then
            echo "appcast.xml not found: ${APPCAST_PATH}"
            exit 1
          fi

          if ! grep -q 'sparkle:edSignature' "${APPCAST_PATH}"; then
            echo "ERROR: appcast.xml does not contain sparkle:edSignature."
            echo "This means the Sparkle EdDSA signing failed silently."
            echo "Check that SPARKLE_PRIVATE_KEY matches the SUPublicEDKey in the app."
            cat "${APPCAST_PATH}"
            exit 1
          fi

          echo "appcast.xml validation passed: EdDSA signature found."
```

## 制約
- `.github/workflows/release.yml` のみを編集すること
- 既存のステップの順序や内容は変更しない（新規ステップ追加のみ）
- コメントの追加は不要

# 修正タスク: CI appcast バリデーションの grep を強化

## 許可事項
ユーザーからの明示的許可: メインブランチで作業してOKです。Worktree/ブランチを切る必要はありません。

## レビュー指摘内容
現在の `grep -q 'sparkle:edSignature'` は文字列の存在だけを確認しており、
`sparkle:edSignature=""`（空値）や不完全な XML でもパスしてしまう。

## 対象ファイル
`.github/workflows/release.yml`

## 修正内容
"Validate appcast.xml contains EdDSA signature" ステップ内の grep を以下に変更:

**変更前:**
```bash
          if ! grep -q 'sparkle:edSignature' "${APPCAST_PATH}"; then
```

**変更後:**
```bash
          if ! grep -Eq 'sparkle:edSignature="[^"]+"' "${APPCAST_PATH}"; then
```

また、エラーメッセージも更新:

**変更前:**
```
            echo "ERROR: appcast.xml does not contain sparkle:edSignature."
```

**変更後:**
```
            echo "ERROR: appcast.xml does not contain a non-empty sparkle:edSignature."
```

## 制約
- `.github/workflows/release.yml` のみを編集
- "Validate appcast.xml contains EdDSA signature" ステップ内の grep 行のみ変更
- 他のステップは一切変更しない

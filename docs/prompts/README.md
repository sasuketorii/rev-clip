# Reviewer Prompt Templates

このディレクトリは、**レビュワープロンプトのテンプレート**を格納する場所です。

## 責務

| ディレクトリ | 用途 |
|-------------|------|
| `docs/prompts/` | **テンプレート**（再利用可能なプロンプト定義） |
| `.agent/active/prompts/` | **実運用**（作業中のハンドオーバー/レビュー依頼） |
| `.agent/archive/prompts/` | **アーカイブ**（完了したプロンプト） |

## 使用方法

カスタムレビュワーを追加する場合、このディレクトリにプロンプトファイルを配置します。

```bash
# 例: セキュリティ特化レビュワーを追加
cat > docs/prompts/security_reviewer.md << 'EOF'
# Security Reviewer

## 観点
- SQLインジェクション
- XSS
- 認証・認可の脆弱性
- 機密情報のハードコード

## 出力フォーマット
docs/roles/reviewer.md に従うこと
EOF
```

## 参照箇所

以下のスクリプトがこのディレクトリを参照しています：

- `.claude/commands/auto_orchestrate.sh`
- `.claude/commands/lib/coder.sh`
- `.claude/commands/lib/reviewer.sh`

## 関連ドキュメント

- `docs/roles/reviewer.md` - Reviewer の詳細ワークフロー
- `.agent_rules/RULES.md` - 共通ルール

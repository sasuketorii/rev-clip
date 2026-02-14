# レビュー依頼: スニペット保存後に白紙になるバグの修正

## AGENT_ROLE=reviewer

あなたはコードレビュワーです。以下の変更をレビューしてください。

## 変更概要
スニペットエディタで新規スニペットを保存後、別のスニペットを選択してから戻ると内容が白紙になるバグの修正。

## 根本原因
`NSTextView.string` は内部の可変バッキング文字列（`NSBigMutableString`）への参照を返す。
保存時にそのまま辞書に保持すると、後続のスニペット切替時に `self.contentTextView.string = ...` で文字列実体が書き換わり、辞書内の値まで連動して変化してしまう。

## 変更ファイル
`src/Revclip/Revclip/UI/SnippetEditor/RCSnippetEditorWindowController.m`

## 変更内容（diff）

```diff
@@ -689,7 +690,7 @@

     RCSnippetNode *snippetNode = (RCSnippetNode *)selectedItem;
     NSString *title = [self normalizedTitleFromField:self.titleField fallback:NSLocalizedString(@"Untitled Snippet", nil)];
-    NSString *content = self.contentTextView.string ?: @"";
+    NSString *content = [self.contentTextView.string copy] ?: @"";
     NSString *folderIdentifier = [self stringValueFromDictionary:snippetNode.parentFolder.folderDictionary
                                                              key:@"identifier"
                                                     defaultValue:@""];
```

## レビュー観点
1. **正確性**: `[self.contentTextView.string copy]` で可変バッキング文字列の参照問題は解決するか？
2. **安全性**: `copy` の呼び出しタイミングと nil 安全性に問題はないか？ `?: @""` との組み合わせは正しいか？
3. **網羅性**: ファイル内に同様のパターン（`self.contentTextView.string` をモデルに保持）が他にないか？見落とした箇所がないか？
4. **副作用**: この変更がパフォーマンスや他の機能に影響を与えないか？

## レビューのフォーマット
- 問題があれば具体的に指摘してください
- 問題がなければ「LGTM」と明記してください
- 各観点について簡潔に判定を記載してください

## レビューに必要なコンテキスト
変更箇所周辺のコードを実際のファイルから読み取って確認してください:
- `saveButtonClicked:` メソッド全体（680行〜720行付近）
- `refreshEditorForSelection` メソッド全体（593行〜660行付近）
- ファイル全体で `self.contentTextView.string` を検索し、他に同様の問題がないか確認

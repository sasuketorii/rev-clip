# タスク: スニペット保存後に白紙になるバグの修正

## 許可事項
ユーザーからの明示的許可: メインブランチで作業してOKです。Worktree/ブランチを切る必要はありません。

## バグ概要
スニペットエディタで新規スニペットを作成・保存後、別のスニペットを選択してから戻ると、内容が白紙になる。ウィンドウを閉じて再度開くと正しく表示される。

## 根本原因（調査済み）
`NSTextView.string` は内部の可変バッキング文字列（`NSBigMutableString`）への参照を返す。
`saveButtonClicked:` で `self.contentTextView.string` をそのまま `updatedSnippetDictionary[@"content"]` に代入すると、後続のスニペット切替で `refreshEditorForSelection` が `self.contentTextView.string = ...` を実行した際に、辞書内の値も連動して書き換わってしまう。

Objective-C の最小再現コードでも確認済み:
```
NSTextView *tv = [[NSTextView alloc] initWithFrame:...];
tv.string = @"first";
NSString *captured = tv.string;
dict[@"content"] = captured;
tv.string = @"second";
// → dict[@"content"] は "second" に変化（期待は "first"）
```

## 対象ファイル
`src/Revclip/Revclip/UI/SnippetEditor/RCSnippetEditorWindowController.m`

## 修正内容

### 修正箇所1: saveButtonClicked: メソッド内（693行目付近）
**変更前:**
```objc
NSString *content = self.contentTextView.string ?: @"";
```

**変更後:**
```objc
NSString *content = [self.contentTextView.string copy] ?: @"";
```

### 修正箇所2: 同様のパターンがないか確認
ファイル全体で `self.contentTextView.string` をモデルや辞書に保持している箇所を全て確認し、`copy` が必要な箇所には同様に修正を適用すること。

同様に `self.titleField.stringValue` など他のUI要素からの文字列取得でも、モデルに保持する場合は `copy` を検討すること（ただし `NSTextField.stringValue` は `NSTextView.string` と異なり内部バッファを共有しないことが確認済みなので、必須ではない）。

## 制約
- このファイル（`RCSnippetEditorWindowController.m`）のみを編集すること
- `saveButtonClicked:` メソッド内の修正が主な対象
- コメントの追加は不要
- 最小限の変更に留めること

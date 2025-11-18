# MouseJumpUtility

最前面ウインドウの相対位置へマウスカーソルをジャンプさせる。  
optionキーでタイトルバーへ、他キーとの組み合わせで四隅や中央をポイントし、移動やリサイズを効率化する。

## Requirements

macOS Tahoe 26.1で動作確認

## Installation

[最新のリリース](https://github.com/fruitjuice088/MouseJumpUtility/releases) から `MouseJumpUtility.app` をダウンロードし、`/Applications` にコピーして利用してください。

## Features

| Keys | Jump to |
|------|---------|
| `⌥` | タイトルバー |
| `⌥` + `W` | 左上 |
| `⌥` + `E` | タイトルバー |
| `⌥` + `R` | 右上 |
| `⌥` + `S` | 左下 |
| `⌥` + `D` | 中央 |
| `⌥` + `F` | 右下 |

## Logging

ログを確認するには以下のコマンドをターミナルで実行する。
```bash
log show --predicate 'subsystem == "com.fruitjuice088.MouseJumpUtility"'
```

## Build from Source

```bash
./build.sh
open MouseJumpUtility.app
```

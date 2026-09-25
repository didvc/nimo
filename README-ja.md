[English](README.md) · 日本語 · [繁體中文](README-zh-TW.md) · [简体中文](README-zh.md) · [Deutsch](README-de.md) · [Français](README-fr.md)

# nimo

*Nim製のターミナル用テキストエディタ。*

Nimの標準ライブラリだけで書かれた、小さく扱いやすいターミナル用テキストエディタです。nanoにならっていて（ショートカットが見つけやすく、画面下部にヒントバーがあります）、それでいてVSCodeから来た人にもなじみやすい作りです。ファイルツリーのサイドバーに作業ディレクトリ全体が表示され、エディタのタブが上部に並び、マウスでファイルをクリックしたり、タブを切り替えたり、カーソルを置いたりできます。

![自身のソースツリーを編集している nimo](images/screenshot.png)

## 機能

- カレントディレクトリのファイルツリーのサイドバー（デフォルトで表示）。
- 変更を示すドット付きのエディタタブ。マウスまたは `Ctrl+W` で閉じられ、収まりきらないほどタブを開くとタブ列が横にスクロールします。
- マウス対応：ファイルをクリックして開く、タブをクリックして切り替える、ホイールでポインタの下にあるペインをスクロール。
- UTF-8を考慮した編集、アンドゥ／リドゥ、保存時点のインジケータ。
- スマートケース検索、行ジャンプ、単語単位のカーソル移動。
- `Ctrl+Z` でシェルに一時停止し、`fg` できれいに再開。
- 外部ライブラリは不要。必要なのはNimの標準ライブラリだけです。

## 対応プラットフォーム

Linux、macOS/BSD、Windowsで同じコードベースを共有しており、異なるのは `term.nim` だけです。

| プラットフォーム | 状況 |
| --- | --- |
| Linux | 対応（2.2.10で動作確認） |
| macOS / BSD | 対応（同じPOSIXバックエンド） |
| Windows 10 1703+ | 対応（10.0.19045、Nim 2.2.4 + mingw64で動作確認） |

Windowsではコンソールを VT モード（`ENABLE_VIRTUAL_TERMINAL_INPUT` / `ENABLE_VIRTUAL_TERMINAL_PROCESSING`）に切り替えるため、POSIXのターミナルと同じエスケープシーケンスを扱え、デコーダ全体を共有できます。ただし、Windowsでは次の違いが避けられません。

- `Ctrl+Z` による一時停止にはジョブ制御が必要ですが、Windowsにはそれに相当するものがありません。このキーは利用できないことを知らせ、ヒントバーには代わりに `^G Goto` が表示されます。
- ウィンドウのリサイズは `SIGWINCH` で通知されるのではなく、ポーリングで検出します。
- ブラケットペーストは使えません。レガシーコンソールはこれを実装しておらず、ConPTYはマーカーを取り除くため、貼り付けは通常のキー入力として届きます。貼り付け自体は高速です（入力ループが再描画の前にまとめて読み切ります）が、貼り付けた文字は1文字ずつ別のアンドゥ単位になるため、貼り付け後の `Ctrl+U` は貼り付け全体ではなく1文字ずつ取り消します。

特にマウス対応のために、レガシーのコンソールホストよりWindows Terminalをおすすめします。ファイルはどのプラットフォームでも `\n` の改行で書き込まれます。

## ビルド

Nim 2.0以上が必要です（2.2.10で動作確認）。取得する依存関係はありません。

```sh
nim c -d:release --out:nimo src/nimo.nim
```

nimbleを使う場合:

```sh
nimble build          # ./nimo を生成
nimble run            # ビルドしてカレントディレクトリを開く
```

## 実行

```sh
./nimo                # カレントディレクトリをルートにしてエディタを開く
./nimo path/file      # 指定したファイルを開く（なければ作成）
```

## キーバインド

### 共通
| キー | 動作 |
| --- | --- |
| `Ctrl+S` | 保存（バッファに名前がなければ名前を尋ねる） |
| `Ctrl+X` | 終了（`Ctrl+Q` も可。未保存の変更があれば確認） |
| `Ctrl+B` | ファイルツリーのサイドバーの表示を切り替え |
| `Ctrl+O` | ファイルツリーにフォーカスを移して閲覧・オープン |
| `Ctrl+Z` | シェルに一時停止（`fg` で再開。POSIXのみ） |
| `Shift+Tab` | エディタとツリーの間でフォーカスを切り替え |

### エディタペイン
| キー | 動作 |
| --- | --- |
| 矢印キー / `Home` / `End` | カーソルを移動 |
| `Ctrl+←` / `Ctrl+→` | 単語単位で移動 |
| `Ctrl+Home` / `Ctrl+End` | ファイルの先頭／末尾へ移動 |
| `PageUp` / `PageDown` | 1画面分スクロール |
| `Ctrl+F` | 検索（スマートケース。`Ctrl+N` で直前の検索を繰り返す） |
| `Ctrl+G` | 行番号へ移動 |
| `Ctrl+U` / `Ctrl+R` | アンドゥ／リドゥ（`Ctrl+Y` でもリドゥ） |
| `Ctrl+A` / `Ctrl+E` | 行頭／行末（nano風） |
| `Ctrl+W` | 現在のタブを閉じる |
| `Ctrl+PageUp` / `Ctrl+PageDown` | 前／次のタブへ切り替え |

### ファイルツリーペイン
| キー | 動作 |
| --- | --- |
| `↑` / `↓` | 選択を移動 |
| `→` / `←` | フォルダを展開／折りたたみ（またはフォルダに入る／出る） |
| `Enter` | ファイルを開く、またはフォルダを展開／折りたたみ |
| `n` | 選択中のフォルダに新しいファイルを作成 |
| `r` / `F5` | ディスクからツリーを再読み込み |
| `Tab` | エディタにフォーカスを戻す |

### マウス
| 操作 | 結果 |
| --- | --- |
| ツリーの項目をクリック | ファイルを開く、またはフォルダを展開／折りたたみ |
| タブをクリック | そのタブに切り替え。`×` / `●` マークをクリックすると閉じる |
| `‹` / `›` をクリック | タブ列があふれているときにスクロール |
| テキスト内をクリック | その位置にカーソルを置く |
| ホイール | ポインタの下にあるツリー、テキスト、またはタブ列をスクロール |

## 設計メモ

コードは4つのモジュールに分かれています。`term.nim` はrawモード、キーとマウスのデコード、ブラケットペースト、ウィンドウのリサイズ、シェルへの一時停止を扱います。2つのプラットフォーム用バックエンド（POSIXではtermios／シグナル、WindowsではコンソールAPI）を1つのインターフェースの裏に持ち、エスケープシーケンスのデコーダは両者で共有しています。`textbuffer.nim` は編集の中核で、UTF-8を考慮し、タブ展開を含む表示位置の計算、アンドゥ／リドゥの履歴、スマートケース検索を備えます。`filetree.nim` は遅延読み込みでキャッシュされるサイドバーのモデルです。`nimo.nim` はこれらを描画と入力ループでつなぎます。

開いたファイルはそれぞれ独立したバッファで、カーソルとスクロール位置もファイルごとに持ちます。すでに開いているファイルをツリーから開くとそのタブに切り替わるので、知らないうちに何かが破棄されることはありません。カーソル移動、削除、横スクロールはいずれも文字（rune）単位で、画面上の表示幅を考慮します。ステータスバーの変更ドットは保存時点を正確に追跡するので、保存時点までアンドゥで戻ると消えます。バイナリらしいファイルや20 MBを超えるファイルは、壊してしまわないよう開くのを拒否します。

## テスト

```sh
nim c -r tests/test_buffer.nim   # 編集コアのユニットテスト
python3 tests/pty_smoke.py       # pty経由で実際のTUIを操作
python3 tests/pty_suspend.py     # Ctrl+Z による一時停止／再開を確認
```

最初の2つはCIで実行されます。`pty_suspend.py` はローカル専用です。POSIXは孤立したプロセスグループに送られた `SIGTSTP` を破棄するため、対話セッションのないCIランナーでは Ctrl+Z でプロセスを止められないからです。

## スクリーンショット

上の画像は、このリポジトリから `scripts/screenshot.sh` で生成しています。このスクリプトはtmuxのペイン内でnimoを操作し、取得した画面を [freeze](https://github.com/charmbracelet/freeze) で描画します。

<!-- BEGIN gh-mutual-linking -->

---

### Related projects

- [lpchart](https://github.com/didvc/lpchart): Chart InfluxDB line protocol in your terminal. Browse measurements, fields and tag sets interactively without knowing what is in the file first.
- [totp](https://github.com/tui-apps/totp): Terminal TOTP authenticator: live 2FA codes with countdown (RFC 6238, Go, Bubble Tea)
- [calc](https://github.com/tui-apps/calc): Live terminal calculator: evaluates arithmetic as you type, no Enter key (Go, Bubble Tea)
- [note-cli](https://github.com/didvc/note-cli): Markdown Indexing and Pcre Regular Expression Compatible Full Text Searching for Advanced Note Takers.
<!-- END gh-mutual-linking -->

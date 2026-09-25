[English](README.md) · [日本語](README-ja.md) · [繁體中文](README-zh-TW.md) · 简体中文 · [Deutsch](README-de.md) · [Français](README-fr.md)

# nimo

*用 Nim 编写的终端文本编辑器。*

一个小巧、好上手的终端文本编辑器，只使用 Nim 标准库编写。它受 nano 启发（快捷键易于发现，底部有提示栏），同时也让从 VSCode 转过来的人感到顺手：文件树侧边栏显示整个工作目录，编辑器标签页排列在顶部，并且可以用鼠标点击文件、切换标签页和放置光标。

![nimo 正在编辑自己的源码树](images/screenshot.png)

## 功能

- 当前工作目录的文件树侧边栏，默认显示。
- 带“已修改”圆点的编辑器标签页，可用鼠标或 `Ctrl+W` 关闭；打开的标签页多到放不下时，标签栏会横向滚动。
- 鼠标支持：点击文件即可打开，点击标签页即可切换，滚轮滚动指针所在的窗格。
- 支持 UTF-8 的编辑、撤销／重做，以及保存点指示。
- 智能大小写搜索、跳转到指定行，以及按单词移动光标。
- `Ctrl+Z` 挂起回到 shell，并可用 `fg` 干净地恢复。
- 无需外部库，唯一的依赖是 Nim 标准库。

## 平台

Linux、macOS/BSD 和 Windows 共用同一套代码，只有 `term.nim` 不同。

| 平台 | 状态 |
| --- | --- |
| Linux | 支持（已在 2.2.10 上测试） |
| macOS / BSD | 支持（同一个 POSIX 后端） |
| Windows 10 1703+ | 支持（已在 10.0.19045 上配合 Nim 2.2.4 + mingw64 测试） |

在 Windows 上，控制台会切换到 VT 模式（`ENABLE_VIRTUAL_TERMINAL_INPUT` / `ENABLE_VIRTUAL_TERMINAL_PROCESSING`），因此可以使用与 POSIX 终端相同的转义序列，整个解码器也得以共用。不过在 Windows 上，以下差异无法避免：

- `Ctrl+Z` 挂起需要作业控制（job control），而 Windows 没有对应的机制。按下该键会提示不可用，提示栏则改为显示 `^G Goto`。
- 窗口大小的变化通过轮询检测，而不是通过 `SIGWINCH` 通知。
- 无法使用括号粘贴（bracketed paste）：旧版控制台从未实现这一功能，而 ConPTY 会去掉标记，因此粘贴的内容会以普通按键的形式到达。粘贴本身仍然很快（输入循环会在重绘前一次读完整批输入），但每个粘贴的字符都是独立的撤销步骤，所以粘贴后按 `Ctrl+U` 会一次撤销一个字符，而不是整段粘贴的内容。

推荐使用 Windows Terminal，而不是旧版控制台主机，尤其是为了鼠标支持。所有平台上的文件都以 `\n` 换行写入。

## 构建

需要 Nim >= 2.0（已在 2.2.10 上测试）。没有需要下载的依赖。

```sh
nim c -d:release --out:nimo src/nimo.nim
```

或者通过 nimble：

```sh
nimble build          # 生成 ./nimo
nimble run            # 构建并打开当前目录
```

## 运行

```sh
./nimo                # 以当前目录为根目录打开编辑器
./nimo path/file      # 打开（或创建）指定的文件
```

## 快捷键

### 全局
| 按键 | 操作 |
| --- | --- |
| `Ctrl+S` | 保存（如果缓冲区还没有名字，会询问文件名） |
| `Ctrl+X` | 退出（`Ctrl+Q` 也可以；如有未保存的内容会要求确认） |
| `Ctrl+B` | 切换文件树侧边栏 |
| `Ctrl+O` | 将焦点移到文件树，以浏览并打开文件 |
| `Ctrl+Z` | 挂起回到 shell（用 `fg` 恢复；仅限 POSIX） |
| `Shift+Tab` | 在编辑器和文件树之间切换焦点 |

### 编辑器窗格
| 按键 | 操作 |
| --- | --- |
| 方向键 / `Home` / `End` | 移动光标 |
| `Ctrl+←` / `Ctrl+→` | 按单词移动 |
| `Ctrl+Home` / `Ctrl+End` | 跳到文件开头／结尾 |
| `PageUp` / `PageDown` | 滚动一屏 |
| `Ctrl+F` | 查找（智能大小写；`Ctrl+N` 重复上一次搜索） |
| `Ctrl+G` | 跳转到指定行号 |
| `Ctrl+U` / `Ctrl+R` | 撤销／重做（`Ctrl+Y` 也可以重做） |
| `Ctrl+A` / `Ctrl+E` | 行首／行尾（nano 风格） |
| `Ctrl+W` | 关闭当前标签页 |
| `Ctrl+PageUp` / `Ctrl+PageDown` | 切换到上一个／下一个标签页 |

### 文件树窗格
| 按键 | 操作 |
| --- | --- |
| `↑` / `↓` | 移动选中项 |
| `→` / `←` | 展开／折叠文件夹（或进入／退出文件夹） |
| `Enter` | 打开文件，或展开／折叠文件夹 |
| `n` | 在选中的文件夹中新建文件 |
| `r` / `F5` | 从磁盘刷新文件树 |
| `Tab` | 将焦点移回编辑器 |

### 鼠标
| 操作 | 结果 |
| --- | --- |
| 点击文件树条目 | 打开文件，或展开／折叠文件夹 |
| 点击标签页 | 切换到该标签页；点击其 `×` / `●` 标记可关闭 |
| 点击 `‹` / `›` 箭头 | 标签栏溢出时滚动标签栏 |
| 点击文本内部 | 将光标放在该处 |
| 滚轮 | 滚动指针下方的文件树、文本或标签栏 |

## 设计说明

代码分为四个模块。`term.nim` 负责原始模式（raw mode）、按键与鼠标解码、括号粘贴、窗口大小变化以及挂起到 shell；它把两种平台后端（POSIX 上的 termios／信号，Windows 上的控制台 API）封装在同一个接口之后，转义序列解码器则由两者共用。`textbuffer.nim` 是编辑核心：支持 UTF-8，包含展开 Tab 后的显示位置计算、撤销／重做日志以及智能大小写搜索。`filetree.nim` 是延迟加载并带缓存的侧边栏模型。`nimo.nim` 则通过渲染和输入循环把它们连接起来。

每个打开的文件都是独立的缓冲区，拥有各自的光标和滚动位置。从文件树打开一个已经打开的文件时，会直接切换到它的标签页，因此不会在你不知情的情况下丢弃任何内容。光标移动、删除和水平滚动都以完整字符（rune）及其在屏幕上的显示列宽计算；状态栏中的“已修改”圆点会精确跟踪保存点，因此撤销回到保存点时圆点就会消失。看起来是二进制文件或超过 20 MB 的文件会被拒绝打开，以免被损坏。

## 测试

```sh
nim c -r tests/test_buffer.nim   # 编辑核心的单元测试
python3 tests/pty_smoke.py       # 通过 pty 操作真实的 TUI
python3 tests/pty_suspend.py     # 检查 Ctrl+Z 挂起／恢复
```

前两项在 CI 中运行。`pty_suspend.py` 只在本地运行，因为 POSIX 会丢弃发送给孤儿进程组的 `SIGTSTP`，所以在没有交互式会话的 CI 运行器上，Ctrl+Z 无法停止进程。

## 截图

上面的图片是用 `scripts/screenshot.sh` 从本仓库生成的：它在 tmux 窗格中操作 nimo，再用 [freeze](https://github.com/charmbracelet/freeze) 渲染捕获到的画面。

<!-- BEGIN gh-mutual-linking -->

---

### Related projects

- [lpchart](https://github.com/didvc/lpchart): Chart InfluxDB line protocol in your terminal. Browse measurements, fields and tag sets interactively without knowing what is in the file first.
- [totp](https://github.com/tui-apps/totp): Terminal TOTP authenticator: live 2FA codes with countdown (RFC 6238, Go, Bubble Tea)
- [calc](https://github.com/tui-apps/calc): Live terminal calculator: evaluates arithmetic as you type, no Enter key (Go, Bubble Tea)
- [note-cli](https://github.com/didvc/note-cli): Markdown Indexing and Pcre Regular Expression Compatible Full Text Searching for Advanced Note Takers.
<!-- END gh-mutual-linking -->

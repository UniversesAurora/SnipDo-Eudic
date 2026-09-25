# SnipDo → 欧路词典划词浮窗

在 SnipDo 中选中文字，点击“欧路查词 v2”，使用欧路词典的原生划词浮窗显示释义。无需欧路自身的划词监听。

适用于 Windows、SnipDo 和欧路词典。桥接逻辑曾在 SnipDo 3.0.87.0 与 Microsoft Store 版欧路词典 26.9.1.0 上验证；本次修订后的扩展包尚未在 SnipDo 中点击测试。

## 安装

1. 安装并启动 [SnipDo](https://snipdo-app.com/) 和欧路词典。
2. 下载本仓库的 [SnipDo-Eudic-v2.pbar](./SnipDo-Eudic-v2.pbar)，双击导入 SnipDo。v2 使用新的扩展 ID 和文件名，以避开旧版本的导入缓存。
3. 在 SnipDo 的 **Settings → Text extensions** 中禁用或删除旧的“欧路查词”，确认新的“欧路查词 v2”已启用，并拖到方便点击的位置。
4. 在欧路词典中关闭 **开启划词翻译功能**。如果不使用“双击 Ctrl+C 取词”或“剪贴板取词”，也将它们关闭。

选中一个单词后点击 SnipDo 工具栏上的“欧路查词 v2”即可。建议在 SnipDo 的 **Show when** 中启用 **Doubleclick** 和 **Mouse drag**，关闭不需要的 **Ctrl+C / Ctrl+X / Ctrl+A** 触发项。在 SnipDo 全局设置中关闭 **Always copy when selecting text**，以免每次选词都改写剪贴板。

如果 SnipDo 没有关联 `.pbar` 文件，可在 SnipDo 的扩展导入入口选取该文件。扩展源文件位于 [extension](./extension/)。

## 工作原理

SnipDo 把选中文字作为 `$PLAIN_TEXT` 传给 [main.ps1](./extension/main.ps1)。这个入口是完整的单文件脚本，不使用 `$PSScriptRoot` 或嵌套函数参数声明，因为 SnipDo 的脚本编辑器会在自己的 PowerShell 运行环境中处理这些内容。脚本把文字编码为 UTF-8 URL 路径段，再调用欧路：

```text
eudic.exe "eudic://cap-dict/<encoded-text>"
```

`cap-dict` 是当前 Windows 版欧路可用的内部入口；欧路尚未公开保证它在未来版本保持兼容。脚本会优先使用已经运行的欧路程序路径，随后查找 Microsoft Store 包及常见安装位置，因此欧路更新后通常不需要改路径。

桥接本身不会模拟按键，也不会读取或改写剪贴板。它保留文本内部的空格、换行、中文和标点；极长文本会报错，不会静默截断。运行错误会写入 `%LOCALAPPDATA%\EudicSnipDo\bridge.log`；日志不含选中文字。

扩展的单色书本图标取自 [SnipDo 官方 Dictionary 扩展](https://snipdo-app.com/wp-content/uploads/2023/09/Dictionary.pbar)；彩色图标使用欧路词典程序图标。

## 手动调试

在 PowerShell 中运行：

```powershell
& '.\extension\Open-EudicCapture.ps1' -Text 'serendipity'
```

如果此命令能打开欧路浮窗，而 SnipDo 按钮不起作用，请检查扩展是否启用，以及 SnipDo 是否取得选中文字。SnipDo 在部分应用中无法读取选区；Windows Terminal 尤其可能需要先复制选区，再使用 SnipDo 的剪贴板文本快捷键。

## 重新打包

`.pbar` 是 ZIP 格式的 SnipDo 扩展包。将 `extension` 目录中的 `main.ps1`、`snipdo-eudic.json`、`book.svg` 和 `icon.png` 压缩在归档根目录，并把扩展名改成 `.pbar`。不要把 `extension` 文件夹本身包在归档的第一层。

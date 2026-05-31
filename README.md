# Clipboard History for Mac

这是一个 macOS 剪贴板历史工具的第一版工程。它用于记录文字和图片剪贴板历史，并通过快捷键或菜单栏找回和粘贴之前复制过的内容。

## 当前状态

已实现第一版主要功能：

- 文字和图片剪贴板历史
- 本机 SQLite 保存
- 图片缩略图保存和清理
- 搜索弹窗
- 菜单栏入口
- 收藏、删除、清空历史
- 默认 30 天保留，可设置
- 运行中定期清理过期记录
- 可配置快捷键
- 自动粘贴回原来的前台应用
- 设置页和验收记录

## 运行前准备

这是真正的 macOS 原生 App 工程，需要完整 Xcode。

1. 在 Mac App Store 安装 Xcode。
2. 打开一次 Xcode，按提示完成初始组件安装。
3. 在终端运行：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

4. 验证：

```bash
xcodebuild -version
```

如果能看到 Xcode 版本号，就说明环境准备好了。

## 打开和运行

在 Finder 里打开这个文件：

```text
ClipboardHistory.xcodeproj
```

或者在终端运行：

```bash
open ClipboardHistory.xcodeproj
```

在 Xcode 里：

1. 选择顶部的 `ClipboardHistory` scheme。
2. 运行目标选择 `My Mac`。
3. 点击运行按钮。

运行后，应用会出现在 Mac 顶部菜单栏。

## 验证命令

安装并选择完整 Xcode 后，在项目目录运行：

```bash
xcodebuild test -scheme ClipboardHistory -destination 'platform=macOS'
xcodebuild -scheme ClipboardHistory -destination 'platform=macOS' build
```

当前环境还没有完整 Xcode，所以这两条命令暂时会被系统阻塞。轻量静态检查已经通过：

```bash
swiftc -typecheck $(rg --files ClipboardHistory -g '*.swift')
plutil -lint ClipboardHistory.xcodeproj/project.pbxproj
git diff --check
```

## 手动验收清单

完整 Xcode 构建成功后，请按这份文档进行手动检查：

```text
docs/verification/2026-05-31-manual-acceptance.md
```


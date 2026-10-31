[English](README.md) | 简体中文

<div align="center">

![ChemDraw Add-in for Mac，绘制、关闭、继续工作。](assets/banner.svg)

# ChemDraw Add-in for Mac

[下载最新安装包](https://github.com/BoeingART/chemdraw-add-in-for-mac/releases/latest) · [安装指南](docs/installation.md)

</div>

在 ChemDraw 中复制化学结构，即可将可编辑的绘图粘贴到 Word、PowerPoint 或 Excel，双击绘图可继续编辑。在 ChemDraw 中保存后，原 Office 图片会同步更新，编辑窗口保持打开。每个绘图都携带可编辑的源数据和 矢量图形。

## 安装与配置

需要 **macOS 12 或更高版本**，以及已单独安装并激活的 **ChemDraw** 和 **Office for Mac**。支持 Word、PowerPoint 和 Excel。

1. 下载通用 DMG，打开后将应用拖到旁边的 **Applications** 文件夹。从旧版迁移时，先完成当前结构编辑并退出插件，再替换应用。
2. 首次打开应用，“**设置加载项**”会分别检查 Word、PowerPoint、Excel 文件访问、辅助功能及助手就绪状态，只配置已安装的 Office 应用。
3. 按系统提示确认授权。程序会自动注册加载项、验证目录写入与读回并启动助手，检查通过后点击“**完成**”。
4. 后续在应用中选择“**检查更新**”，确认后会自动下载、替换应用并重新打开，保留已有授权、连接证书和草稿。正在编辑的结构会等待编辑结束后再更新。
5. 首次启用 Excel 时，按提示授予 Excel 文件访问及自动化权限。已有 Office 授权缺失时，可打开设置或选择“**修复加载项**”。

关闭窗口后，助手会继续在菜单栏运行。如果隐藏了菜单栏图标，可从“应用程序”重新打开本应用以恢复图标。菜单中会显示当前版本。更新时会显示下载进度，并可取消下载；安装完成后，应用会自动重新打开。

## 粘贴与编辑

1. 打开新建或已有的 Word 文档、PowerPoint 演示文稿或 Excel 工作簿。
2. 在 ChemDraw 中选中结构，按 **⌘C** 复制。
3. 在 Office 中按 **⌘V**、右键选择“**粘贴**”，或点击面板中的“**粘贴可编辑绘图 / Paste editable drawing**”按钮。
4. 双击绘图，在 ChemDraw 中编辑。按 **⌘S** 或选择“**保存**”，即可更新原 Office 图片并继续编辑。关闭该 ChemDraw 文档后，会返回原 Office 文档。
5. 由你决定何时保存 Office 文档。新建且尚未保存的文档也支持直接粘贴、打开和回写化学结构。

编辑期间再次粘贴，会创建独立的绘图。切换窗口或另存为后，原编辑仍对应原来的 Office 文档和 ChemDraw 编辑目标。面板和设置窗口会显示操作进度、具体失败原因及下一步操作。

## 本地数据与恢复

证书、捕获的化学结构和编辑草稿保存在 `~/Library/Application Support/ChemOffice/work`，升级时会保留。各 Office 应用通过各自的沙盒缓存目录交换预览图。

关闭原 Word、PowerPoint 或 Excel 文档时，会保留最新的本地草稿，并关闭对应的 ChemDraw 编辑窗口。双击原绘图可继续中断的编辑。开始另一项编辑时，已关闭的草稿会保留在 `recovery` 目录中。

助手在执行粘贴操作时捕获剪贴板中的化学结构数据，编辑过程在本地完成。可选的 Office 面板连接本地 HTTPS 服务，其 Office.js 库从微软 CDN 加载。

## 构建与验证

从源码构建需要 Apple 命令行工具及 Swift 5.7 或更高版本。运行 `zsh scripts/build.sh` 可为当前架构构建；运行 `zsh scripts/build.sh --universal` 可同时为 Apple Silicon 和 Intel 构建。安装包制作与签名配置见[安装指南](docs/installation.md)。

已完成的检查记录见[安装就绪检查](docs/installation-readiness-results.md)和[未保存 Office 文档检查](docs/unsaved-office-results.md)。练习文档见[示例](examples/README.md)。

版权所有 © 2026 ChemDraw Add-in for Mac 贡献者。根据 [Apache License 2.0](LICENSE) 发布。

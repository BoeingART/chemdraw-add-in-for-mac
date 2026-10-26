## ChemOffice for Mac 1.0.5

安装后即可按窗口引导完成配置，授权后自动启动粘贴助手。

### 更新内容

- 新增“完成安装”窗口，分别显示 Word、PowerPoint 文件访问和辅助功能状态。
- 自动配置加载项并检查绘图缓存读写权限，授权后自动重试。
- 辅助功能授权后自动启动助手，收到键盘与鼠标监听就绪信号后显示完成。
- 可通过菜单栏或重新打开 ChemOffice 返回设置，启动失败时可直接重新检查。
- 新建、尚未保存的 Word 和 PowerPoint 文档支持直接粘贴与编辑。

### 安装与使用

打开 **ChemOffice-for-Mac-1.0.5-universal.pkg**，按安装器步骤更新。升级前完成当前绘图编辑并退出 ChemOffice。

在“完成安装”窗口点击设置按钮，为 ChemOffice 开启 Microsoft Word、Microsoft PowerPoint 文件访问以及辅助功能。系统授权由你确认，后续配置和助手启动会自动完成。全部通过后点击“开始使用”。

升级后若 Office 文件访问开关自动关闭，请按[安装指南](https://github.com/BoeingART/chemoffice-plugin-for-mac/blob/v1.0.5/docs/installation.md#office-permission-switches-turn-off-after-an-upgrade)重新申请访问权限。

在 ChemDraw 中复制结构，到 Office 按 ⌘V 粘贴。双击结构编辑，用 ⌘W 返回；Office 文档由你手动保存。

使用 Office 面板时，先保存手头工作并重启 Office。Office 2021 使用“插入 → 我的加载项”的下拉菜单；新版 Office 使用“开始 → 加载项”。如面板提示本地连接证书问题，在 ChemOffice 菜单选择 Trust Local Connection 完成认证。

支持 Apple Silicon 和 Intel，适用于 macOS 12 及更新版本。

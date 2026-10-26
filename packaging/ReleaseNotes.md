ChemOffice for Mac v0.1.2

修复标准安装后的 Word 面板证书错误，以及 ChemDraw 26 复制后粘贴为无法打开图片的问题。

### 修复内容

- 同时识别 ChemDraw 26 的 Revvity、旧版 PerkinElmer 和 Carbon CDIF 剪贴板格式。
- 原生事件即时送达，避免粘贴、双击等操作等待管道缓冲区填满。
- 未保存的 Word 文档首次粘贴时提示保存，完成后继续原始粘贴；取消则不插入。
- Word 插入使用原始 SVG 纵横比，保存时验证实际源数据、预览和比例。
- 每次启动检查 localhost SSL 证书信任，允许重新完成此前跳过的授权，并验证授权结果；本地诊断不经过代理。
- 修复关闭 ChemDraw 后因 Word 隐藏文件扩展名而无法返回原文档、结束会话的问题。

### 下载与安装

下载 **ChemOffice-for-Mac-0.1.2-universal.pkg**，按 macOS 安装器步骤安装到 `/Applications/ChemOffice.app`。包含 Apple Silicon 和 Intel 可执行文件，目标系统为 macOS 12 或更新。运行无需 Python、Homebrew、开发工具或源码目录；需要另行安装并激活 ChemDraw、Word 和 PowerPoint。

升级前完成当前编辑并退出 ChemOffice。证书、源数据和恢复草稿保留在本用户 Application Support 目录。安装包未使用 Developer ID 签名、未经 Apple 公证，应用使用 ad-hoc 签名；下载后可用 **SHA256SUMS.txt** 校验。

macOS 27 将原“辅助功能”权限入口命名为“设备控制和数据访问”。升级后若开关已开启但助手仍提示未授权，请移除旧的 ChemOffice 条目，重新添加 `/Applications/ChemOffice.app` 并启用，再重启 ChemOffice。不要修改其他应用的权限。

若 Word 仍提示安全证书无效，从 ChemOffice 菜单选择 **Trust Local Connection**，完成 macOS 认证，再保存文档并完全重启 Office。本机 HTTPS 证书与应用/安装包的 Developer ID 签名是两件事。

### 验证范围

- 50 项原生回归检查、ChemDraw 自动发现检查，以及通用 pkg 的双架构、签名、依赖、安装器、启动自检和 SHA-256 检查通过。
- 在 **macOS 27.0.1、Word 16.114.1、ChemDraw 26.0.0.6599** 上实测面板加载、⌘C/⌘V、未保存 Word 的保存并继续粘贴、双击打开、⌘W 回写校验并返回 Word。
- 保留 ChemDraw 22 的应用识别和旧剪贴板支持，相关自动检查通过；**0.1.2 与 ChemDraw 22 的完整实机流程尚未验证**。同时安装多个版本时默认选择较新的 ChemDraw。
- 原生 PowerPoint 验收、Intel 实际运行、全新 Mac 和其他版本兼容性仍待验证；历史 Python beta 的实测不代替本次原生版验收。

[中文安装指南](https://github.com/BoeingART/chemoffice-plugin-for-mac/blob/v0.1.2/docs/quickstart-zh.txt) · [Installation guide](https://github.com/BoeingART/chemoffice-plugin-for-mac/blob/v0.1.2/docs/installation.md) · [完整验证记录](https://github.com/BoeingART/chemoffice-plugin-for-mac/blob/v0.1.2/docs/native-paste-certificate-fix-results.md)

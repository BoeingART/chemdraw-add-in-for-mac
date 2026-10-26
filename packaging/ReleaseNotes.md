ChemOffice for Mac v0.1.0 提供原生 macOS 应用和 pkg 安装包。

- 下载 **ChemOffice-for-Mac-0.1.0-universal.pkg**，按 macOS 安装器步骤安装；支持 Apple Silicon 与 Intel，目标系统为 macOS 12 或更新。
- 应用安装至 `/Applications/ChemOffice.app`，安装后通常自动打开。无需 Python、Homebrew、开发工具或源码目录。
- 全部 8 个 `.command` 启动文件已移除；改用菜单栏应用完成助手启停、加载项安装、证书信任、诊断与查看本机数据。
- 首次启动完成本用户的 Office 加载项配置。按提示授权 localhost SSL 证书及辅助功能，再选择 **Start Helper**。macOS 保护 Office 文件夹时，应用提供 Finder 复制步骤。保存文档并重启 Office 后，从“开始 → 加载项 → 开发人员加载项”打开 ChemOffice。
- 证书与恢复草稿存放于 `~/Library/Application Support/ChemOffice/work`，升级应用时保留。旧源码版的 `work` 留在旧目录，请先完成旧编辑并保留需要的草稿。

需要另行安装并激活 ChemDraw、Word 与 PowerPoint。使用流程仍为 ChemDraw ⌘C → Office ⌘V → 双击编辑 → ChemDraw ⌘W 回写；Word 首次粘贴前先保存，未保存的 PPT 会提示保存并自动继续。回写会保存整个 Office 文档。

**签名与验证范围：**本次 pkg 未使用 Developer ID 签名、未经 Apple 公证；应用仅有 ad-hoc 执行签名。如果 macOS 拦截安装包或应用，请在“系统设置 → 隐私与安全性”中选择“仍要打开”。39 项原生检查、ChemDraw 自动发现测试、双架构编译、实际 pkg 解包与签名检查、安装器配置、应用启动和菜单自检、SHA-256 检查已通过。原生重写的真实 Office/ChemDraw 编辑回写、全新 Mac 管理员安装和 Intel 运行验收仍待完成；历史 beta 实测不代表本次原生版已完成同样验收。

安装说明：[中文快速指南](https://github.com/BoeingART/chemoffice-plugin-for-mac/blob/v0.1.0/docs/quickstart-zh.txt) · [Installation guide](https://github.com/BoeingART/chemoffice-plugin-for-mac/blob/v0.1.0/docs/installation.md) · [Validation](https://github.com/BoeingART/chemoffice-plugin-for-mac/blob/v0.1.0/docs/release-0.1.0-results.md)

下载后可用随附 `SHA256SUMS.txt` 校验安装包。

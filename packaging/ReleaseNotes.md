ChemOffice for Mac v1.0.3

修复预览文件反复授权、Office 授权窗口无法操作，以及注册失败后不重试的问题。针对 Office 2021 for Mac 16.78 补充加载项入口和诊断。

### 修复内容

- 预览 SVG 改为存放在 Word / PowerPoint 各自的沙盒缓存目录，避免读取 ChemOffice 私有目录时触发 Office 文件授权。
- Office 正在粘贴、保存或回写时，正常放行键盘和鼠标，对话框可操作、可取消；回写期间仍保护 ChemDraw 当前绘图窗口。
- 安装时校验两个加载项清单的实际内容，并探测预览目录写入权限。注册失败不再记为安装成功；后续启动检查缺失或过期清单并重试。
- 单个 Office 注册失败不会跳过另一个，保留其他加载项；诊断显示具体主机、版本、清单与预览目录状态。
- Office 2021 / 16.78 使用“插入 → 加载项 → 我的加载项”的下拉菜单，查看“开发人员加载项 → ChemOffice for Mac”。激活后出现 ChemOffice 标签。
- 源数据、恢复草稿和证书继续保留在 Application Support。若预览目录无法访问，会保留草稿并报错，不再使用旧的外部预览路径。

### 安装

使用 **ChemOffice-for-Mac-1.0.3-universal.pkg**，安装至 `/Applications/ChemOffice.app`。升级前完成当前编辑并退出旧版 ChemOffice。安装后允许 macOS 访问 Office 文件夹，选择 Check Installation 确认清单校验结果；若提示未完成，选择 Install Office Add-ins 重试。保存文档并完全退出、重新打开 Word / PowerPoint。

包含 Apple Silicon 和 Intel 可执行文件，目标系统为 macOS 12 或更新。运行无需 Python、Homebrew、开发工具或源码目录。安装包未使用 Developer ID 签名、未经 Apple 公证。

### 验证

- 61 项原生回归检查、ChemDraw 发现检查、微软 manifest 校验及通用 pkg 自检通过。
- 在 macOS 27.0.1、Word / PowerPoint 16.114.1 实测沙盒内 SVG 插入和再次读取回写，保存后的源数据、预览和尺寸校验通过；未出现针对 SVG 的授权窗口。
- **Office 2021 / 16.78 的实机加载项显示仍需验证**。本次沙盒烟雾测试不代替完整安装后复制、双击和 ChemDraw 编辑流程验收。

[完整验证记录](https://github.com/BoeingART/chemoffice-plugin-for-mac/blob/v1.0.3/docs/office-sandbox-registration-fix-results.md) · [中文安装指南](https://github.com/BoeingART/chemoffice-plugin-for-mac/blob/v1.0.3/docs/quickstart-zh.txt)

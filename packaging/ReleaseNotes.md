# 2.0.0 本地构建 35

- 修复开启修订的Word文档中，保存化学结构后出现重复对象和回写失败的问题，保留已有修订记录及修订开关状态。
- 操作失败直接弹窗显示具体原因和重试方式，编辑草稿继续保留。
- 安装后按“设置加载项”窗口检查授权；助手就绪后继续使用。

# 2.0.0 本地构建 34

- 修复 Windows 复制、编辑并保存后的 Word ChemDraw 对象无法打开的问题。
- 为重复标记的对象建立独立编辑标识，打开和保存回写准确对应所选结构。
- 修复面板打开原生对象时的 Word 文档定位问题。
- 安装后按“设置加载项”窗口检查授权；助手就绪后继续使用。

# 2.0.0 本地构建 33

- 打开位于后续页面的结构时，自动滚动到结构所在位置，保留原结构坐标。
- 复用同一份保存快照的预览，减少重复生成开销。
- 当前 OLE 回写采用内容替换，Office 内部对象 ID 会变化。
- 完整保存速度尚未达到两秒目标。
- 本地测试构建，尚未完成 Apple 公证。安装后按“设置加载项”窗口检查授权。

# 2.0.0 本地构建 32

- 修复跨页及位于后续页面的化学结构粘贴，保留结构的相对位置、绘图设置和字体。
- 复用本地 Office 通信进程，减少重复启动开销。
- 更新后按“设置加载项”窗口检查授权；助手就绪后可继续使用。

## ChemDraw Add-in for Mac 2.0.0 — Development

### 中文

- 修复直接双击原 Windows ChemDraw OLE 时出现的“无法找到服务器应用程序”错误，直接在 Mac ChemDraw 打开结构。
- 支持在 Mac ChemDraw 编辑 PowerPoint 内的 Windows ChemDraw OLE。⌘S 和菜单“保存”更新对应结构的嵌入内容，并保持编辑窗口打开。
- 在 PowerPoint 粘贴 Mac CDX 时创建原生 ChemDraw OLE；新建且未保存的 PPT 可直接插入和回写，切换文稿后仍更新原目标。
- 同步期间保留后续输入。OLE 文件提取与副本导出继续提供；Word／Excel 的 OLE 接入继续开发。

### English

- Fix the server-application error when double-clicking original Windows ChemDraw OLE objects. Open their structures directly in Mac ChemDraw.
- Edit Windows ChemDraw OLE drawings from PowerPoint in Mac ChemDraw. Command-S and menu Save update the corresponding embedded drawing content and keep the editor open.
- Create native ChemDraw OLE when pasting Mac CDX into PowerPoint. Insert and update in unsaved presentations, and retain the original target when switching documents.
- Preserve subsequent input during synchronization. OLE extraction and copy export remain available; Word/Excel OLE integration is in development.

# OLE 保存同步与原生身份验证记录

## 2026-11-04 当前要求与 Windows 机制对照

用户已明确允许更换原 Office 对象及其内部 ID，要求同步更新结构数据和预览。原生对象身份保留已从当前验收条件中移除。Office 文档由用户决定何时保存、未保存的新文档可用、定位原目标文档、使用独立保存快照以及保持 ChemDraw 编辑窗口打开等要求继续适用。

Revvity 的[官方 ChemDraw 介绍，第 7 页](https://revvitysignals.com/sites/default/files/2024-11/rs-e-book-every-chemist-can-draw-with-chemdraw%20-%20.pdf)确认 Windows Office 支持双击打开 ChemDraw，并在 Office 中显示编辑结果。底层流程依据微软公开的 OLE 协议推导，ChemDraw 内部的具体接口调用顺序尚未核实。

| 环节 | Windows 标准 OLE 机制 | 当前 Mac 插件代码 |
| --- | --- | --- |
| 保存结构数据 | 嵌入对象通过 `IOleClientSite::SaveObject` 请求容器保存；容器通过 `IPersistStorage` 保存对象内容。 | `NativeBridge.synchronize` 取得已保存内容的独立快照；`ChemDrawOLE.create` 在捕获的原 OLE 存储副本中更新 `CONTENTS`。 |
| 更新显示 | OLE 缓存可从数据对象刷新显示内容；视图变化通过通知交给容器处理。 | `ChemDrawOLE.create` 更新 `OlePres` 预览流；传输文档同时提供 Office 所需的匹配预览。 |
| 交回打开的文档 | Office 和 ChemDraw 通过 OLE 的容器与服务器连接交换内容。 | Word 覆盖原 EMBED 范围；PowerPoint、Excel 导入并验证新对象后删除旧对象。 |

协议依据为微软的 [SaveObject](https://learn.microsoft.com/en-us/windows/win32/api/oleidl/nf-oleidl-ioleclientsite-saveobject)、[IPersistStorage::Save](https://learn.microsoft.com/en-us/windows/win32/api/objidl/nf-objidl-ipersiststorage-save)、[UpdateCache](https://learn.microsoft.com/en-us/windows/win32/api/oleidl/nf-oleidl-iolecache2-updatecache) 和 [OnViewChange](https://learn.microsoft.com/en-us/windows/win32/api/objidl/nf-objidl-iadvisesink-onviewchange)。这些文档描述的接口面向 Windows。

当前代码已具备结构数据与预览同步路径。允许对象替换后，可沿用该路径满足内容同步要求；此前未通过的原生身份测试作为历史证据保留。原有动画、交互触发器、超链接及其他附加属性的迁移，以及保存性能，仍按各自验证结果评估。

本次完成公开协议与本地代码对照，更新验收范围。未改动运行代码或重新进行 Office 应用测试。

## 2026-11-03 历史要求与结论

当时用户要求保留原 OLE 内部 ID，适用于 Word 和 PowerPoint；当时的对象替换方案未通过该项验收。

已安装的本地版本为 2.0.0 Build 32。多页预览修复已在 Word 和 PowerPoint 中验证。原 OLE 内部 ID 保留仍未实现。

补充案例发现 CDXML 在后部页面仍有空白预览问题。本机 ChemDraw 22 对页面模式接受小写 `poster`；大写 `Poster` 仍按分页裁切。仅修改大小写的对照测试已确认原因，源代码已修复。九个原生预览案例通过，包括后部页面的 CDXML 与 CDX、跨四页结构、立体键、电荷／同位素、中文反应标注、彩色图形、30 个独立片段及空白画布；预览与 ChemDraw 原生 PDF 对照通过，输入文件保持原样。日志为 `build/ole-build33/preview-cases-fixed.log` 和 `build/ole-build33/preview-native-late.log`。本次源代码修复尚未安装，Word／PPT 解锁后的回写验收结果见后文。

现有 Word 回写把隐藏文档中的格式化 EMBED 范围赋给原范围。PowerPoint 回写先粘贴新 OLE，再删除旧 OLE。这两条路径保留插件的结构标记，但没有原生对象存储写入能力。

## 已检查的入口

| 入口 | 结果 |
| --- | --- |
| 本机 Word 16.114.1 AppleScript 字典 | inline shape 有只读的 anchorID、editID、field 以及可写的尺寸、替代文本；没有 OLE 存储写入属性或 OLEFormat.Object 入口。 |
| 本机 PowerPoint 16.114.1 AppleScript 字典 | shape 提供几何、外观、动画及链接属性；没有可写的嵌入 OLE 数据属性。 |
| PowerPoint 直接给原 shape 赋值 | 在独立测试演示文稿中返回 -10006，未接受赋值。日志为 `build/ole-inplace-acceptance/capability.log`。 |
| Word 对整个 EMBED 范围执行文件导入 | 测试产生两个对象、两个字段；已撤回此尝试。日志为 `build/ole-build33/word-direct-probe.log`。 |
| 现有 PPTX 存储直接重写 | 离线文件路径能够保留图形节点并改写嵌入内容；修改磁盘文件不会同步当前打开文档的内存对象。 |
| 独立的本机 COM 探索 | 未取得可操作的 Office 对象句柄，探索代码仅留在 build 目录。 |

Microsoft 的 [Office for Mac VBA 文档](https://learn.microsoft.com/en-us/office/vba/api/overview/office-mac)说明 Mac Office 不支持第三方 COM 加载项。其 [PowerPoint OLEFormat.Object 文档](https://learn.microsoft.com/en-us/office/vba/api/powerpoint.oleformat.object)描述通过创建应用的顶层接口访问嵌入对象。两份文档结合本机接口检查，尚不能给出适用于此 Mac ChemDraw 对象的原位写入实现。

Revvity 的 [ChemDraw 产品功能表](https://revvitysignals.com/sites/default/files/2025-06/Full%20Dot%20Chart%20ChemDraw%20Suite%20of%20Products.pdf)将 Copy ChemDraw Structures as OLE Object 和 Insert OLE Object in ChemDraw 标为 Windows 功能。

自动保存用户文档、修改文件后重新打开，会改变用户控制保存的流程，也无法用于未保存的新文档，因此没有采用。

## 对象替换路径的具体缺点

根据当时回写代码检查，替换路径存在以下缺口。当时用户要求保留原内部 ID，因此未将此路径认作可接受的原位编辑实现。

| 项目 | 当前实现和影响 |
| --- | --- |
| Office 原对象身份 | Word 赋值整个 EMBED 范围，PPT 删除旧形状并粘贴新形状。插件标记相同，原 Office 对象存储仍被更换。 |
| PPT 原对象附加属性 | `ole-update-prepare` 与捕获结果只保留幻灯片、位置、宽度、旋转等信息；新对象高度按新预览比例计算。该路径没有迁移原对象的动画、交互触发器、超链接、堆叠顺序、翻转或形状效果，相关复杂文稿尚未通过兼容性验收。 |
| 可见对象数量 | PPT 在 `ole-paste-stage` 验证新增对象后才于 `ole-update-commit` 删除旧对象，存在同时保留两者的阶段。Word 使用隐藏暂存文档，用户文档的对象数量检查已通过，但整段范围赋值仍是替换。 |
| 撤销与失败恢复 | Word 已测试替换前后失败恢复。PPT 提交代码先删除原对象，再重命名和读回新对象；删除原对象之后的失败恢复尚未完成实际验收。 |
| 性能 | 创建传输文件、Office 导入、复制与验证均需时间。现有 2.61–2.92 秒 Word 测量是替换路径的桥接事务，尚无符合原 ID 条件的端到端三秒实测。 |

上述结论来自 `office/word/adapter.applescript` 的 `ole-update-stage`／`ole-update-replace`，以及 `office/powerpoint/adapter.applescript` 的 `ole-update-prepare`／`ole-paste-stage`／`ole-update-commit`。附加属性的缺失是代码检查结果，具体 Office 表现仍需独立测试文稿验证。

## 独立的性能工作

开发代码已避免重复渲染同一份保存快照的 PNG。只有 SVG 内容完全相同时才复用预览；后续结构使用自己的预览。此改动尚未安装，也尚未测得安装版本的端到端节省时间。

Word 传输文件原先重复使用固定的 VML/OLE 标识。改为独立的传输标识后，12 次连续保存的桥接事务为 2.61–2.92 秒，每次回读均与对应保存源一致，测试 Office 文档保持未保存。该测量来自对象替换路径，另计开发环境文件授权耗时；不能用于通过原位编辑验收，也没有达到最初要求的两秒保存目标。日志为 `build/ole-build33/unique-id-repeat.log`。

## 历史身份验收方式

新增显式身份核对模式：

```sh
CFM_OLE_SAVE_SAMPLES=1 zsh scripts/test-ole-performance-live.sh identity
```

此模式只创建、保存和关闭自己的测试文档。它核对实际 DOCX 中的 ObjectID、ShapeID，以及 PPTX 中的 OLE 图形 ID；保存前后变化即失败。同时仍检查嵌入的 ChemDraw 源数据。它会保留测试快照供复查。

测试先连续保存一份未修改的测试文档，确认保存操作本身不会改变所比较的 ID。ID 比较是必要检查；实现仍须直接写入原对象存储，给新对象复用同一段标识文本也不能通过原位编辑验收。

解锁后已运行身份核对。测试文件通过单独的文件 URL 预检交给 Office，仅第一次另存为，后续对同一文件执行普通保存并保留只读副本。正常性能模式仍测试全新且未保存的 Office 文档。

Word 的普通保存对照会重建 `ObjectID`，因此测试把此字段标为不稳定，继续检查其他字段，整体不判通过。Word 内存 `anchorID` 在普通保存对照中保持为 `0`，插件回写后变为 `381338170`。PPT 的形状 ID 在保存对照中保持为 `2`，插件回写后变为 `3`。两条回写路径仍未达到原内部 ID 保留要求。日志为 `build/ole-build33/identity-live-control-save.log` 和 `build/ole-build33/identity-live-word-anchor-late.log`。

## 本轮自动检查

`scripts/test-native.sh` 完整运行通过，包含 23 个核心检查、132 个事务检查、48 个 OLE 检查、21 个 PDF 矢量检查和 3 个独立脚本进程协议测试；本轮最终日志为 `build/ole-build33/native-regression-viewport.log`。九个原生 ChemDraw 预览案例也通过，日志为 `build/ole-build33/preview-nine-cases-valid-pages.log`。工作区差异和本地化生成检查通过。

## 解锁后的实际应用结果

九个 CDX 案例分别在 Word 和 PPT 中完成粘贴、打开和一次保存回写，共 18 组。全部确认回读 CDX 与对应保存源一致，OLE 内部缓存预览与独立保存快照逐字节一致，Office 测试文稿保持未保存。打开与自动滚动没有改写源文件，也没有使 ChemDraw 文档进入未保存状态；每组关闭测试文稿后，Office 文稿数量回到测试前的数量。

后部页面结构打开时停在首页空白处的问题已修复。新逻辑读取结构和完整画布边界，严格匹配当前 CFM 文件窗口，仅调整滚动条。第 45 页附近结构已经通过实际界面检查；原结构坐标和字体保持不变。

| 指标 | Word | PowerPoint |
| --- | ---: | ---: |
| 打开及定位，九个案例范围 | 0.53–1.51 秒 | 0.87–1.18 秒 |
| 保存回写事务，九个案例范围 | 2.99–3.16 秒 | 2.97–3.33 秒 |

这轮使用与正式构建相同的 `-O -whole-module-optimization` 设置。Word 开发程序的单文件访问预检另计并从事务时间扣除；ChemDraw 原生保存、已安装助手的保存检测与排队耗时另计。三秒端到端保存目标尚未通过。完整结果为 `build/ole-build33/office-case-matrix-viewport-release/results.json`，逐组日志位于同目录。

本机 ChemDraw 22 的隔离渲染试验未进入产品。其框架缺少 26 版预览接口，并在读取文档时报告缺少 `PreferenceManager` 服务。试验使用 build 目录内的独立副本，原 ChemDraw 应用保持原样。

用户要求不再持续追加测试，现有测试到此收尾。本轮新增修复已生成 2.0.0 Build 33 本地安装包，安装包版本、签名、双架构及打包检查通过。包尚未完成 Apple 公证，未发布到 GitHub。电脑仍安装 Build 32，尚未安装新包。原内部 ID 保留和用户要求的两秒端到端保存仍未完成。

# Hey UI 重构设计文档（iOS 极简方向）

> 制定日期：2026-06-05
> 关联：功能规划见 [`development-plan.md`](development-plan.md)；本文件只管 **界面与交互**，不涉及功能闭环。
> 原则：**简洁明了，又不丢信息**——信息靠层级和留白区分，而非堆叠卡片与装饰。

---

## 一、设计方向（已锁定）

经与作者对齐，确定如下基调：

| 维度 | 决策 | 备注 |
| --- | --- | --- |
| 视觉风格 | **iOS 极简** | 大留白、弱化阴影/描边、分组列表、大标题、少量强调色 |
| 配色 | **沿用现有暖橙主题** | 不重做色板，复用 `theme/Theme.ets` + `resources/{base,dark}/element/color.json` |
| 导航 | **底部 3-Tab，取代抽屉** | 连接 / 节点 / 设置 |
| 首要痛点 | ①导航藏太深（抽屉+溢出菜单） ②节点列表/操作 | 本次重点解决①，②部分解决 |

### 导航结构

```
┌──────────────────────────────────────────┐
│   ① 连接        ② 节点         ③ 设置        │  ← 底部 TabBar
│   ic_shield     ic_globe       ic_settings  │
└──────────────────────────────────────────┘
```

- **① 连接** — 只做"连不连"：大连接环 + 状态 + 当前节点选择行 + 流量/时长统计卡
- **② 节点** — 只做"选/管节点"：大标题 + 搜索 + 溢出操作菜单（可见）+ 订阅分组分段 + 节点列表
- **③ 设置** — 取代抽屉：iOS 分组列表，聚合所有配置入口，复用既有子页面

---

## 二、设计令牌（复用，勿硬编码）

代码里只引用语义令牌，不写十六进制。来源：`theme/Theme.ets`。

- **颜色**：`AppColor.brand / surface / surfaceAlt / textPrimary/Secondary/Tertiary / success / danger / divider / border …`（明暗自动适配）
- **间距**：`Space.xs(4) sm(8) md(12) lg(16) xl(20) xxl(24) xxxl(32)`
- **圆角**：`Radius.sm(8) md(12) lg(16) xl(20) pill`
- **字号**：`FontSz.caption(11) footnote(12) body(14) callout(15) headline(17) title(20) display(26)`
- **阴影**：`Elevation.card/raised/glow` + `AppColor.shadowCard/shadowBrand`

### iOS 化的取舍约定

- 卡片：圆角 `Radius.lg`，阴影尽量不用或极轻；用 `surface` 与 `bg` 的色差区分层级
- 列表：分组用 `surface` 块 + `Radius.lg`，行间 `0.5px` `divider` 细线，左侧留出图标缩进
- 标题：每个 Tab 顶部 `FontSz.display` 大标题
- 强调色 `brand` 只用于：选中态、连接态、当前项、主操作——不滥用
- **单一暖色强调**：全站不再使用蓝色系。原 `info` 蓝（资源页/分应用/对话框等）已统一为 `brand` 橙；左滑「详情/编辑」等次要操作用中性灰 `textSecondary` 与橙色「分享」区分；`success` 绿 / `danger` 红 作为语义状态色保留。`info`/`info_tint` 令牌现已闲置（保留备用）

---

## 三、各页面重构进度

> 状态：✅ 完成（iOS 重排+令牌化）· 🌓 仅深色令牌化（iOS 重排待做）· 🚧 进行中 · ⬜ 未开始 · ➖ 暂不动

| 页面 | 文件 | 状态 | 说明 |
| --- | --- | --- | --- |
| 应用骨架 / 底部 Tab | `pages/Index.ets` | ✅ | 抽屉→3-Tab，逻辑全保留 |
| 连接 Tab | `pages/Index.ets` | ✅ | 连接环 + 当前节点行 + 统计卡 |
| 节点 Tab | `pages/Index.ets` | ✅ | 标题/搜索/可见操作菜单/分组分段/列表 |
| 设置 Tab | `pages/Index.ets` | ✅ | iOS 分组列表，聚合 9 个入口 |
| 节点卡片 | `features/servers/ServerCard.ets` | ✅ | 精简为 国旗+名称+协议/地址+延迟+选中勾；操作改左滑 |
| 节点列表 | `pages/Index.ets` `NodeList` | ✅ | 升级为原生 `List`，行间细分割线，左滑「分享/详情/删除」 |
| 通用页头（全站） | `shell/PageHeader.ets` | ✅ | 改用令牌；细底分割线；统一带动 15 个子页页头 |
| 分组标签（共享） | `components/SectionHeader.ets` | ✅ | 品牌大标题→iOS 灰色小分组标签 |
| 设置行控件（共享） | `features/settings/SettingsControls.ets` | ✅ | 令牌化；隐藏开发者键名；语言改分段控件 |
| 设置偏好页 | `pages/Settings.ets` | ✅ | iOS 分组卡片；灰底+白卡+细分割线；品牌色保存按钮 |
| 订阅分组页 | `pages/Subscriptions.ets` | ✅ | 分组改 iOS 列表行（图标+名称+信息+开关/箭头）；操作改左滑 |
| 路由设置页 | `pages/Routing.ets` | ✅ | iOS 分组列表：流量模式/域名策略改单选行（右侧 ic_check），预置规则集改导航行（chevron→详情弹窗） |
| 分应用代理页 | `pages/PerApp.ets` | ✅ | iOS 分组：主开关/过滤策略(单选行)/系统应用开关/应用列表(头像+包名+勾选)/手动添加(输入行+品牌按钮)；隐藏开发者键名，启用既有 perApp.* 文案 |
| 资源文件页 | `pages/Assets.ets` + `pages/assets/*` | ✅ | iOS 分组：快捷操作/内置 Geo/自定义资源/备份还原四组卡片；BuiltinGeoCard 改纯分组卡内容；CustomAssetList 改 PageHeader+左滑列表（更新/编辑/删除）；弹窗令牌化 |
| 日志页 | `pages/Logs.ets` `LogPanel`/`RuntimePanel` | 🌓 | 深色已适配；iOS 重排待做 |
| 扫码页 | `pages/Scanner.ets` | 🌓 | 深色已适配；系统扫码 UI 不重排 |
| 关于页 | `pages/About.ets` | 🌓 | 深色已适配；iOS 重排待做 |
| 节点详情/编辑 | `pages/NodeDetail.ets` `NodeEdit.ets` | ✅ | NodeDetail 改信息组+JSON 组+危险删除行；NodeEdit 卡片标题→SectionHeader、子控件令牌化、保存按钮简化为品牌 pill |
| 导入/JSON/导出 | `pages/Import.ets` `JsonImport.ets` `Export.ets` | 🌓 | 深色已适配；iOS 重排待做 |
| 订阅详情/编辑 | `pages/SubscriptionDetail.ets` `SubscriptionEdit.ets` + 面板 | 🌓 | 深色已适配；iOS 重排待做 |

---

## 四、已完成详情（首页，2026-06-05）

### 改动文件
- `pages/Index.ets` — 视图层完全重构成 3-Tab；**所有 controller 逻辑（连接/选节点/测速/订阅更新/导出等）原样保留**
- `core/I18n.ets` — 新增 `tab.*`、`home.*`、`settings.group.*`、`settings.row.preferences`、`nodes.searchPlaceholder` 中英文文案
- 新增图标 `resources/base/media/ic_shield.svg`（连接）、`ic_globe.svg`（节点）
- 清理 5 个重构后失效的私有方法（heroSubText / bottomStatusText / localizeCoreMessage / deleteCurrentConfig / showRealConnectionTestUnavailable）

### 关键交互决策
- **溢出菜单解散**：原右上角 9 项菜单 → 节点 Tab 顶部可见菜单（更新订阅/测速/去重/清理无效/导出/服务重启/定位）；删掉了无实际作用的「删除配置」「真连接测速（仅提示不可用）」
- **当前节点行**点击 → `TabsController.changeIndex(1)` 跳到节点 Tab 选节点
- 程序化切 Tab 用 `TabsController`，高亮用 `@State currentTab` 驱动自定义 `tabBar` builder

---

## 五、待验证（本机无 DevEco/hvigor，未编译预览）

以上为人工逐行核对的代码，**尚未在 DevEco 编译或真机运行**。需重点验证：

- [x] 底部 Tab 点击高亮是否实时切换（自定义 `tabBar` builder 的状态响应）
- [ ] "当前节点"行点击能否跳到节点 Tab
- [ ] 节点 Tab 搜索框展开后宽度/边距正常
- [ ] 三个 Tab 大标题在真机状态栏下方是否被遮挡（当前沿用原内边距，未额外加安全区 inset）
- [ ] 深浅色模式下卡片/分割线层级是否清晰

---

## 六、下一步

1. 子页面逐页统一为 iOS 分组列表风格（下一个：路由页 `Routing.ets` → 分应用 `PerApp.ets` → 资源页 `Assets.ets`）
2. 安全区 inset 统一处理（若真机验证发现遮挡）
3. 待真机验证左滑操作手感后，决定删除是否加二次确认

### 左滑操作待验证项
- [ ] `ListItem.swipeAction` 在圆角裁剪的 `List` 上左滑显示是否正常
- [ ] 三个左滑按钮（分享/详情/删除）高度是否撑满行高
- [ ] 删除为即时生效（无二次确认），与旧版一致

---

## 七、继续工作指引（新会话从这里接手）

> 新会话没有上一段对话的上下文，**先读完本文件再动手**。以下是接手所需的全部约定与状态。

### 当前状态
- **分支**：`redesign/home-ios-minimal`（基于 `main`），已有 6 个提交，未推送。
- 已完成 ✅：底部 3-Tab 首页（连接/节点/设置）、节点卡片+列表左滑、设置页、订阅页、通用页头 PageHeader、共享组件令牌化、**全站子页面深色模式令牌化**、**配色统一为暖橙（无蓝）**、**App Logo 暖橙重设计**。
- **尚未在 DevEco 编译/真机验证**——所有 ArkTS 均为人工逐行核对。每次改完用括号/圆括号配对自检，但仍需真机走查（见上方各「待验证」清单）。

### 下一步（按优先级）
1. ~~路由页 `pages/Routing.ets` 的 iOS 分组重排~~ ✅ 已完成。
2. 其余 🌓 页面逐个 iOS 重排：~~`PerApp.ets`~~ ✅ → ~~`Assets.ets`(+`assets/*`)~~ ✅ → ~~`NodeDetail/NodeEdit`~~ ✅ → `Import/JsonImport/Export`（下一个） → `SubscriptionDetail/SubscriptionEdit` → `About` → `Logs`。
3. 安全区 inset 统一处理（若真机发现大标题被状态栏遮挡）。

### iOS 分组重排的样板（务必照此保持一致）
参照已完成的 `pages/Settings.ets`，模式固定为：
- 页面根：`.backgroundColor(AppColor.bg)`（灰底）；顶部 `PageHeader`；内容放 `Scroll > Column({ space: Space.lg })`。
- 每组：`SectionHeader({ title })`（iOS 灰色小标签）+ 一个分组卡片 `Column(){...}.backgroundColor(AppColor.surface).borderRadius(Radius.lg).clip(true).margin({left:Space.lg,right:Space.lg})`。
- 组内每行之间用细分割线 `Divider().strokeWidth(0.5).color(AppColor.divider).margin({left:Space.lg})`。
- 可选行：右侧用 `ic_check`（`AppColor.brand`）表示选中；导航行右侧用 `ic_chevron_right`。
- 颜色/间距/圆角/字号**只用令牌**（`AppColor/Space/Radius/FontSz`），禁止硬编码 hex。
- 列表项的「分享/编辑/删除」等操作优先用 `List + ListItem.swipeAction` 左滑（参照 `Index.ets` 的 `NodeList`、`Subscriptions.ets`）。

### 提交约定（用户要求，务必遵守）
- 提交信息：**英文、一句话、无任何协作者尾注**（不要 `Co-Authored-By`）。
- **按功能拆分**多个提交，一个功能一个 commit。
- 用 `git add <显式文件清单>` 精确暂存，**不要 `git add -A/.`**。

### 不要触碰 / 不要提交的文件（非本次 UI 工作，属他人改动）
```
docs/roadmap.md
docs/v2rayng-feature-map.md
docs/development-plan.md
docs/v2rayng-analysis/
entry/src/main/ets/core/XrayConfig.ets
```

### 已知保留项（非 bug，勿"修复"）
- `info` / `info_tint` 令牌现已闲置（配色统一后无引用），保留备用，**勿删**。
- 延迟状态色链（`SubscriptionDetail.nodeDelayColor()` / `SubscriptionRows` 的 `delayColor: string`）为 string 类型，仍是硬编码中间调色——深色下可接受。
- `promptAction.Button` 系统弹窗里的颜色字段为数据字段，保留硬编码。

---

## 变更记录

| 日期 | 变更 |
| --- | --- |
| 2026-06-05 | 建立文档；锁定 iOS 极简 + 3-Tab 方向；完成首页（连接/节点/设置 Tab）重构 |
| 2026-06-05 | 节点卡片精简为信息卡；节点列表升级为原生 `List`，操作改 iOS 左滑（分享/详情/删除） |
| 2026-06-05 | 统一通用页头 PageHeader（带动全站子页）；SectionHeader/设置行控件令牌化；设置偏好页改 iOS 分组卡片，隐藏开发者键名 |
| 2026-06-05 | 订阅分组页改 iOS 列表行 + 左滑操作（分享/编辑/删除），与节点列表交互一致 |
| 2026-06-05 | 真机修复三连：①Index 加 `onPageShow` 刷新（加订阅后节点列表实时更新）②PageHeader 覆盖层 `hitTestBehavior(Transparent)` 修复返回键被遮挡失效 ③节点搜索改为 header 内就地展开（搜索框+取消，带动画），不再在下方另开输入框 |
| 2026-06-05 | **子页面深色模式适配**：20 个子页面/组件的硬编码 hex 全量令牌化（~500 处），深色模式自动适配；新增 `infoTint` 令牌（base+dark）。已知保留的 3 处硬编码：①`nodeDelayColor()`/`delayColor` 的延迟状态色链（string 类型约束，中间调在深色下仍清晰）②`promptAction.Button` 系统弹窗色（BuiltinGeoCard） |
| 2026-06-05 | **配色统一为单一暖橙**：全站 `info`/`infoTint` 蓝 → `brand`/`brandTint` 橙；左滑次要操作改中性灰；延迟「测速中」蓝改橙。无蓝色残留 |
| 2026-06-05 | **节点详情/编辑页 iOS 分组重排**：`NodeDetail` 改灰底 + 节点信息组（名称/协议/来源信息行）+ 使用按钮（品牌/成功 pill）+ Outbound/原始链接分组卡 + 底部危险「删除」行；TextArea 透明融入卡片。`NodeEdit` 各表单卡片的品牌色标题条 → `SectionHeader`，卡片去阴影、改纯分组卡；`SegmentedControl`/`ToggleRow`/`PickerRow`/`EditorRow` 全令牌化（输入框 surfaceAlt + Radius.md，开关补 brand 选中色）；底部保存按钮由渐变+阴影+按压缩放简化为品牌 pill（禁用态 surfaceAlt），移除未用的 `isPressed` 状态与 blur。表单拼装与校验逻辑（saveManualNode 等）原样保留 |
| 2026-06-05 | **资源文件页 iOS 分组重排**：`Assets.ets` 三张品牌色卡片 → 灰底 + `SectionHeader` 四组（快捷操作/内置 Geo/自定义资源/备份还原），统一 `EntryRow`（图标圈+标题+副标题+可选 chevron）。`BuiltinGeoCard` 去掉内部标题/阴影，改为纯分组卡内容（下载源行 + geosite/geoip 行 + 0.5px 细分割线）。`CustomAssetList` 自定义头改用统一 `PageHeader`（新增可选 `onBack` 回调），列表行内三按钮 → iOS 左滑（更新/覆盖导入·编辑·删除），底部「添加」改品牌 pill。`AssetAddEditDialog` 数值令牌化、按钮改 pill + i18n 文案。promptAction 删除按钮 hex 按既定约定保留 |
| 2026-06-05 | **PageHeader 增强**：新增可选 `onBack: () => void`（默认 `router.back()`），向后兼容；供在页内子视图（如 CustomAssetList）复用统一页头并自定义返回行为 |
| 2026-06-05 | **分应用代理页 iOS 分组重排**：单层固定布局 → 启用时整页 `Scroll` + 分组卡片（主开关 / 过滤策略黑白名单单选行 + 系统应用可见性开关 / 应用列表：圆形首字母头像+包名+勾选 / 手动添加：输入行 + 品牌按钮），关闭时居中占位。`SettingToggleRow` 改传空键名隐藏开发者键；黑白名单/系统可见性改用既有 `perApp.*` 中英文案；移除未用的 `bundleManager`/`ActionListItem` 导入与 `InputLabelPair` 子组件。逻辑（开关/名单/勾选/手动追加/persist）原样保留 |
| 2026-06-05 | **路由页 iOS 分组重排**：三张品牌色卡片 → 灰底+`SectionHeader`+分组卡片。流量模式/域名策略由分段控件/自定义单选改为 iOS 单选行（图标+标题+副标题，右侧 `ic_check` 标选中），流量模式说明改组脚注；预置规则集改导航行（`ic_chevron_right`，点击仍弹详情）。去除卡片阴影，间距/圆角/字号全部令牌化。逻辑（trafficMode/strategy/routeOnly/persist）原样保留 |
| 2026-06-05 | **App Logo 重设计**：保留「H+连接节点」图形语义，蓝色渐变 → 暖橙渐变 + 底部柔光波纹，青绿节点环改白色。SVG 源 `design/app-icon/hey-icon-{fg,bg,combined}.svg`，已渲染部署 foreground/background（AppScope + entry）与 startIcon(144) |

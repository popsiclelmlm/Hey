# Hey 真机测试计划（singbox-preview 分支）

> 目标设备：**ALN-AL80 / HarmonyOS 6.1.0.117(SP6C00E115R4P9) / API 23**（hdc 设备号 `29Q0223920001682`）
> 这正是此前"点连接必崩（VPN 扩展没有回写启动完成状态）"的设备，本轮所有 P0 用例都以"在它上面不再崩、能上网"为验收基线。
> 版本基线：分支 `singbox-preview`，含工作区未提交改动（tun2socks 数据面 + AnyTLS + 扫码内联 + 测速 TaskPool 化 + sing-box 预览核）。

---

## 0. 本轮改动总览（决定测试优先级）

| 改动 | 影响面 | 优先级 |
|---|---|---|
| **VPN 数据面改 tun2socks**：`TUN fd → libheytun2socks.so → 内核 SOCKS 入站(127.0.0.1:10810) → outbound`（Xray 与 sing-box 统一走此路） | 所有 VPN 连接 | **P0（本轮核心）** |
| **删除 `testNativeXrayConfig` preflight** | VPN 启动路径，避免冷 cgo SIGSEGV | **P0** |
| **AnyTLS 分享链接解析**（`anytls://`，ShareLinkParser.ets:785) | 导入/订阅/扫码 | P1 |
| **扫码内联化**（QrScan.ets + Subscription Detail/Edit 不再跳 Scanner 页） | 订阅扫码 | P1 |
| **延迟测速移到 TaskPool**（DelayTester.ets，`@Concurrent`) | 节点测速 | P1 |
| **sing-box 第二核（预览）**：已改走 tun2socks + 本地 SOCKS 入站（同 Xray 数据面，不再用原生 TUN/OpenTun） | 核心切换 | P2（验证可连/降级/报错） |
| **临时诊断改动**（XrayConfig 写死 debug 日志落盘 / HeyVpnAbility precreateDiagnosticLogs） | 日志、隐私、性能 | 回归项，需确认后回退 |

---

## 1. 环境与准备

### 1.1 设备与工具
- [ ] 真机已开启「开发者模式 + USB 调试」，`hdc list targets` 能看到 `29Q0223920001682`
- [ ] 抓日志：`hdc shell hilog -r && hdc shell hilog | grep -iE "hey|vpn|xray|tun2socks|singbox|SIGSEGV"`
- [ ] 崩溃栈：复现崩溃后 `hdc file recv /data/log/faultlog/faultlogger/ ./crash/`（或 `hdc shell ls /data/log/faultlog/faultlogger`）
- [ ] **干净安装**：`hvigor clean` → 重新打包 → 卸载旧版 → 安装（避免残留 .so / preferences 干扰）

### 1.2 测试数据（提前备好真实可用节点）
为覆盖配置生成，准备以下真实节点（分享链接 + 二维码各一份）：
- [ ] VLESS + Reality（TCP）
- [ ] VLESS + WS + TLS
- [ ] VLESS + gRPC + TLS
- [ ] VMess + WS + TLS
- [ ] Trojan + TCP + TLS
- [ ] Shadowsocks（AEAD，如 aes-128-gcm / chacha20）
- [ ] Hysteria2（Xray 专属，sing-box 不支持）
- [ ] **AnyTLS**（`anytls://` 本轮新增）
- [ ] 一条可用的**订阅 URL**（含多个节点）
- [ ] 一个 QR 图片存到相册（用于相册扫码）

### 1.3 通过标准（全局）
- 任一 P0 用例出现 **SIGSEGV / 进程 `com.lmlm.hey:vpn` 秒退 / 12s 内无回写** = 阻断性缺陷。
- 流量统计、连通性以「实际能打开外网 + 速度数值合理变化」为准。

---

## 2. P0 — 冒烟与 VPN 数据面（tun2socks）

> 这是本轮的验收主线。重点验证 ALN-AL80 上**不再复现 TLS 墙崩溃**。

### TC-S01 安装与冷启动
1. 干净安装后首次冷启动 App。
- 预期：主页正常渲染，无白屏/闪退；首启权限弹窗（如有）正常。

### TC-S02 默认核（Xray）VPN 首连 —— 核心验收
前置：核心保持默认 Xray；选中一个 VLESS+Reality 节点；模式 = VPN。
1. 点击主页大按钮「连接」。
2. 观察 hilog。
- 预期：
  - hilog 出现 `Native VPN bridge started.`，**无 SIGSEGV**，进程 `com.lmlm.hey:vpn` 不秒退。
  - 状态变「已连接」，开始计时。
  - 用浏览器/被墙站点验证**真的能上网**（数据面通）。
  - 上/下行流量数值随使用增长。

### TC-S03 断开
1. 已连接状态下点「断开」。
- 预期：状态回「未连接」；流量停止；hilog 见 tun2socks + xray 均 stop；再次进入应用无残留连接。

### TC-S04 各协议连通性（逐个过）
对 §1.2 每个协议（除 Hysteria2 单列）重复：选中 → 连接 → 验证上网 → 断开。
- [ ] VLESS+Reality / VLESS+WS+TLS / VLESS+gRPC / VMess+WS / Trojan / Shadowsocks
- 预期：均能连通、能上网、断开干净。

### TC-S05 AnyTLS 端到端
前置：已通过分享链接导入 AnyTLS 节点（见 TC-L01）。
1. 选中 AnyTLS 节点 → 连接。
- 预期：能连上并上网。**若内核不识别 AnyTLS** → 启动应失败并有清晰错误（不应崩溃/卡死），记录为内核能力缺口而非阻断。

### TC-S06 DNS over UDP（重点回归）
> 数据面改 SOCKS 入站后，UDP/DNS 是高风险点（文档 §9.5 待办列了 "DNS-over-UDP 是否需加固"）。
1. 连接后，访问纯靠 DNS 解析的新域名（清缓存/换站点）。
2. 测试 UDP 业务（如可用，QUIC 站点 / 视频）。
- 预期：域名能解析、网页能开；记录是否出现「首次解析慢/偶发失败」。

### TC-S07 启停压力 / 快速重连
1. 连接→断开 连续 10 次。
2. 连接后立即断开再连接（快速操作）。
- 预期：无崩溃、无端口占用残留（10810/10808）、无「上次未清理」导致的连不上。

### TC-S08 切换节点重连
1. 已连接 A 节点 → 直接选 B 节点。
- 预期：按产品设计（自动重连或提示先断开）正确处理，数据面切到 B，能上网。

### TC-S09 流量统计准确性
1. 连接后下载一个已知大小文件。
- 预期：下行累计与实际量级吻合（tun2socks 字节计数接管，见 napi GetStats）；不出现「归零跳变 / 长期不动」。

### TC-S10 模式：仅代理（Proxy Only，Xray）
前置：设置 → 模式 = 仅代理。
1. 连接，按提示端口（默认 SOCKS 10808 / HTTP）配置一个客户端走代理。
- 预期：本地代理可用；注意此模式**不经过 tun2socks**，验证未被本轮改动破坏。

---

## 3. P2 — sing-box 第二核（预览）

> sing-box 已与 Xray 一样改走 tun2socks + 本地 SOCKS 入站（不再用原生 TUN/OpenTun/gvisor tun 栈），
> 且用 OHOS Go fork（TLSDESC）构建，理论上不再撞 TLS 墙。本节验证**可连 + 切换/报错/降级**行为。

### TC-C01 核心切换入口
设置 → 内核选择，在 Xray ↔ sing-box 间切换。
- 预期：选项可切换并持久化（重启 App 后保持）；有「预览」字样提示。

### TC-C02 sing-box 启动行为（本机）
前置：核心 = sing-box，选 VLESS/VMess/Trojan/SS 单节点 → 连接。
- 预期：能连上并上网（数据面同 Xray 走 tun2socks → SOCKS 入站）。若启动失败应有清晰错误回写、
  且 App 主进程不跟着崩、UI 能恢复到「未连接」；记录 hilog（含 `sing-box started` / `tun2socks started`）。

### TC-C03 sing-box 不支持的配置应明确报错（不崩）
核心 = sing-box，分别尝试：
- [ ] Hysteria2 节点 → 预期错误「sing-box 暂不支持该节点」
- [ ] 代理链 / 策略组 → 预期错误「仅支持单节点」
- [ ] 仅代理模式 → 预期错误「sing-box 预览暂仅支持 VPN 模式」
- 预期：均为友好报错，不崩溃。

### TC-C04 ⚠️ VPN 运行中切换核心（已知无保护）
> 代码层 `persistCoreType()` 不检查 VPN 状态（潜在 bug）。
1. Xray 连接中 → 设置里切到 sing-box → 返回主页观察。
2. 断开 → 重新连接。
- 预期：记录实际行为。理想为「切换时提示需先断开」或「下次连接才生效且干净」；若出现两核状态混乱（GetStats 误报运行中 / 连不上）→ 报缺陷。

### TC-C05 关于页 sing-box 探针
关于页触发 `probeNativeSingbox`（dlopen 检查，UI 线程安全）。
- 预期：显示符号加载情况；**不触发** `nativeSingboxVersion`（冷 cgo，UI 线程会 SIGSEGV）—— 确认 UI 上没有任何按钮会冷调版本/version。

---

## 4. P1 — 分享链接 / 订阅解析（AnyTLS 新增 + 回归）

### TC-L01 AnyTLS 链接解析
导入页/订阅页粘贴 `anytls://password@host:port?sni=...&alpn=...&fp=...&insecure=1`。
- 预期：解析成功，生成节点；字段（sni/alpn/fingerprint/insecure）正确落到配置；非法链接给出错误而非崩溃。

### TC-L02 各协议链接解析回归
逐个粘贴 vless:// vmess:// trojan:// ss:// 链接。
- 预期：均正确解析为对应节点（确认新增 AnyTLS 分支未破坏既有解析顺序）。

### TC-L03 订阅添加 / 更新
1. 添加订阅 URL → 更新。
- 预期：HTTP 拉取成功，节点入库，分组显示；含 AnyTLS 的订阅也能解析。
2. 后台/定时更新（如配置）。
- 预期：节点刷新，选中态不丢。

### TC-L04 深链 / 文本分享导入
通过 `hey://install-sub?url=...`、`hey://install-config?...`、外部分享文本触发导入。
- 预期：正确进入导入流程并落库。

---

## 5. P1 — 扫码（QrScan 内联化）

### TC-Q01 订阅编辑/详情页内联扫码
SubscriptionEdit / SubscriptionDetail 点扫码图标。
- 预期：**直接调起系统相机**（不再跳 Scanner 全屏页）；扫到二维码后**自动回填**输入框并停留在当前页。

### TC-Q02 相册扫码
扫码界面选「相册」→ 选 §1.2 准备的二维码图片。
- 预期：识别并回填（`enableAlbum: true`）。

### TC-Q03 权限拒绝 / 取消
- [ ] 首次扫码拒绝相机权限 → 预期：友好 toast/引导，不崩（`isScanCancelled` 对权限码 1000500002 不弹打扰性 toast 需确认设计）。
- [ ] 调起相机后直接返回（取消，码 20001）→ 预期：**不弹** toast，输入框不变。

### TC-Q04 独立 Scanner 页 / 控制卡 / 快捷方式扫码回归
主页节点菜单扫码、`hey://scan`、桌面快捷方式「扫码」。
- 预期：仍走原 Scanner 流程，正常工作（确认内联化没误删共用逻辑）。

---

## 6. P1 — 延迟测速（TaskPool 化）

### TC-D01 单节点测速不卡 UI
节点页点单个节点 ping 图标，同时滚动列表。
- 预期：测速期间 UI 流畅可滚动（已移到 `@Concurrent` worker 线程）；结果显示延迟 ms。

### TC-D02 批量测速
菜单「延迟测试」对整组节点测速。
- 预期：并发跑、结果陆续回填、无卡死；连续多轮无内存/句柄泄漏（观察可重复执行）。

### TC-D03 测速准确性与异常
- [ ] 可用节点 → 合理延迟值
- [ ] 失效节点 / 无效配置 → 显示超时/失败（区分 `invalid-config`），不崩
- [ ] 测速期间启动 VPN / 测速与连接互不干扰

---

## 7. P2 — 其它功能回归

| 用例 | 模块 | 预期 |
|---|---|---|
| TC-R01 | 路由规则（全局/规则/直连、自定义规则、规则集导入、广告拦截） | 规则保存生效，连接后分流正确 |
| TC-R02 | 分应用代理（黑/白名单、预设、手动包名） | 指定 App 走代理/直连符合设置 |
| TC-R03 | 资产管理（GeoIP/Geosite 下载、版本、镜像源、本地导入） | 下载成功、版本更新、路由能用到 |
| TC-R04 | 高级出站（代理链 / 策略组：轮询/随机/最小延迟） | 生成虚拟节点，Xray 下可连（sing-box 下应被拒，见 TC-C03） |
| TC-R05 | 导入：手动协议表单 / JSON 完整配置 / 拖拽 | 各路径都能入库 |
| TC-R06 | 导出：单节点分享链接 / 复制剪贴板 / 导出文件 | 内容正确、可被再次导入（往返一致） |
| TC-R07 | 日志页（实时日志、搜索、导出、运行状态） | 显示 xray/tun2socks 状态，日志滚动正常 |
| TC-R08 | 设置项（主题、显示模式、端口、DNS、IPv6、Mux、超时等） | 改动持久化、连接生效 |
| TC-R09 | 语言切换（9 种语言，重点 zh-CN/zh-TW/en/ar 的 RTL） | 文案切换、无缺失 key、阿拉伯/波斯文 RTL 布局正常 |
| TC-R10 | 桌面卡片 / 控制中心卡片 | 启停、扫码、状态实时刷新 |
| TC-R11 | 快捷方式（Toggle/Start/Stop/Scan） | 各命令正确 |
| TC-R12 | 系统通知（速度通知开关） | 连接时显示上下行速度，可关闭 |
| TC-R13 | 开机自启 | 启用后开机/重启 App 自动连接，首启有提示 |
| TC-R14 | 数据备份/恢复（如系统触发） | 订阅/节点/设置可备份恢复（entrybackupability 当前为空，确认行为） |

---

## 8. 临时诊断改动回退验证（文档 §9.3）

> 这些是排查期临时加的，**确认稳定后必须回退**，否则有隐私/性能问题。测试时先确认其存在与影响，提缺陷跟踪回退。

- [ ] **XrayConfig.ets**：日志级别被写死 `debug` 且落盘 `xray_error.log` / `xray_access.log`。
  - 验证：连接后检查应用沙箱内是否生成这两个文件、是否含敏感连接信息；确认设置里的「日志级别」当前是否被忽略。→ 缺陷：回退为按 `settings.logLevel`。
- [ ] **HeyVpnAbility.ets**：`precreateDiagnosticLogs()` 及 `[临时诊断]` 代码。
  - 验证存在 → 缺陷：回退。

---

## 9. 性能与稳定性

- [ ] TC-P01 长连接：连接后挂 30~60 分钟正常使用，无断流、无内存持续增长、无异常耗电。
- [ ] TC-P02 弱网/切网：连接中 WiFi↔蜂窝切换、断网恢复 → 数据面能恢复或给出可恢复状态，不崩。
- [ ] TC-P03 后台存活：App 切后台/锁屏后 VPN 持续；速度通知保持。
- [ ] TC-P04 内存/句柄：反复测速+连断 20 轮后无明显泄漏（10810/10808 端口、fd 正常回收）。
- [ ] TC-P05 冷启动首连偶发性（文档 §9.5 待办）：重复「冷启动→首连」≥5 次，记录是否偶发不通。

---

## 10. 缺陷记录模板

```
[ID]   TC-编号 / 自由复现
设备   ALN-AL80 / HarmonyOS 6.1 / 版本号
核心   Xray | sing-box
模式   VPN | 仅代理
协议   VLESS-Reality / ...
步骤   1. 2. 3.
预期   ...
实际   ...（附 hilog 关键行 / faultlog 崩溃栈）
等级   阻断 | 严重 | 一般 | 轻微
```

---

## 11. 验收门槛（Go / No-Go）

- **必过（Go 前提）**：TC-S02 / S03 / S04（主流协议）/ S06（DNS）/ S07（启停压力）在 ALN-AL80 上全绿且全程**无 SIGSEGV**。
- **应过**：AnyTLS（L01/S05）、扫码（Q01~Q03）、测速（D01~D03）。
- **可带病发布但需记录**：sing-box 预览（第 3 节）—— 只要不拖垮主进程、报错可控即可。
- **发布前必须回退**：第 8 节临时诊断改动。
</content>
</invoke>

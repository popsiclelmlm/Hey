# v2rayNG 用户界面与功能交互

> 领域四：全部页面清单与职责、主界面交互、服务器编辑、扫码/分享、批量便捷功能、ViewModel 架构。
> 代码位置基于 v2rayNG 源码（`app/src/main/java/com/v2ray/ang/ui` 等）。

## 1. 页面（Activity）清单

### 核心功能页
| Activity | 职责 |
|---------|------|
| MainActivity | 主界面：服务器列表、分组切换、连接开关、测速、导入导出 |
| GroupServerFragment | 分组服务器列表片段：拖拽排序、编辑、分享、删除 |
| ServerActivity | 通用协议编辑（VMess/VLESS/SS/Socks/HTTP/Trojan/WireGuard/Hysteria2） |
| ServerCustomConfigActivity | 自定义完整 JSON 配置编辑 |
| ServerGroupActivity | 策略组（PolicyGroup）配置 |
| ServerProxyChainActivity | 代理链（ProxyChain）配置 |

### 导入导出/扫描
| Activity | 职责 |
|---------|------|
| ScannerActivity | 二维码扫描（摄像头 + 相册图片识别） |
| UrlSchemeActivity | URL Scheme 深链导入（install-config / install-sub） |

### 订阅与资源
| Activity | 职责 |
|---------|------|
| SubSettingActivity | 订阅管理：增删改排序、批量更新、QR 分享 |
| SubEditActivity | 订阅编辑：URL、UA、自动更新间隔、前/后置代理 |
| UserAssetActivity | 资源管理：geoip/geosite 本地上传、URL 导入、自动下载 |
| UserAssetUrlActivity | 资源 URL 编辑 |

### 功能设置
| Activity | 职责 |
|---------|------|
| PerAppProxyActivity | 分应用代理（黑/白名单、搜索、全选/反选/自动选择） |
| RoutingSettingActivity | 路由设置：规则集管理、域名策略、预设导入 |
| RoutingEditActivity | 路由规则编辑（域名/IP/进程 → 出站） |
| SettingsActivity | 全局设置：模式、DNS、分片等 |

### 系统工具
| Activity | 职责 |
|---------|------|
| BackupActivity | 上游提供本地 + WebDAV 备份/恢复；Hey 当前不实现备份 |
| LogcatActivity | 日志查看（搜索/复制/导出/分享） |
| AboutActivity | 关于（版本、源码、许可、隐私） |
| CheckUpdateActivity | 检查应用 / 内核更新 |

### 快捷与特殊
TaskerActivity（Tasker 集成）、AppPickerActivity（通用应用选择器）、ScStart/Stop/Switch/ScannerActivity（快捷方式）。

### 基础框架
BaseActivity（工具栏/文件选择/QR/加载对话框）、HelperBaseActivity、BaseFragment。

## 2. 主界面（MainActivity）交互

布局：DrawerLayout + NavigationView（侧滑菜单）、TabLayout + ViewPager（订阅分组切换）、RecyclerView（服务器列表）、FAB（连接开关）、测试状态区。

- **服务器列表**（`MainRecyclerAdapter.kt:27-233`）：单列显示分享/编辑/删除按钮 + 点击选中；双列显示"更多"菜单；`ItemTouchHelper` 拖拽排序
- **连接开关 FAB**（`:136-203`）：停止→请求 VPN 权限→启动；运行→停止；加载中显示勾选；`ActivityResultContract` 处理 VPN 权限
- **测速**（`:153-160, 307-317`）：`testAllTcping()`（快）/ `testAllRealPing()`（准）；结果经 `TestServiceMessage` 广播 + `updateTestResultAction` LiveData
- **分组切换**（`:118-134`）：`GroupPagerAdapter`，每分组一个 `GroupServerFragment`
- **搜索过滤**（`:216-234`）：`filterConfig()` 实时正则匹配（remarks/描述/地址/协议）

## 3. 服务器编辑

### ServerActivity（通用协议）
按协议加载不同布局（vmess/vless/shadowsocks/socks/trojan/wireguard/hysteria2）。字段：基本信息、协议参数（UUID/加密/flow）、传输层（网络类型/请求头）、TLS（SNI/证书验证/uTLS fp/ALPN）、特殊参数（WireGuard 公钥/MTU、KCP MTU/TTI、XHTTP mode/extra）。保存经 `MmkvManager.encodeServerConfig()`。

### ServerCustomConfigActivity
完整 JSON 编辑（代码编辑器 + JSON 语法高亮），解析为 ProfileItem，运行中则重启服务。

### ServerGroupActivity（策略组）
选择源订阅 + 正则过滤 + 分组类型（Random/RoundRobin/Latency）；字段 `policyGroupSubscriptionId/policyGroupFilter/policyGroupType`。

### ServerProxyChainActivity（代理链）
多代理串联，RecyclerView 显示成员，FAB 添加，AutoComplete 建议成员（排除策略组/代理链/自定义）。

## 4. 扫码 / 分享 / 剪贴板

### 二维码扫描（`ScannerActivity.kt:20-103`）
- 实时摄像头（手电筒/声音/自动焦点）
- 相册图片 → `QRCodeDecoder.syncDecodeQRCode(bitmap)`
- 导入 → `parseUri()` → `AngConfigManager.importBatchConfig()`

### 分享导出（`GroupServerFragment.kt:111-170`）
AlertDialog 选项：显示 QR 码（`share2QRCode`）、分享到剪贴板单行（`share2Clipboard`）、分享完整配置 JSON（`shareFullContent2Clipboard`）、编辑、删除。导出全部 `exportAllServer()`。

### 剪贴板导入（`MainActivity.kt:395-405`）
`importClipboard()` → `importBatchConfig()`，自动识别 vmess/vless/ss/trojan/hysteria2 等。

## 5. 其他功能页面要点

- **PerAppProxyActivity**：代理/旁路两模式；GridLayout 应用列表 + 搜索 + 全选/反选/自动选择代理应用/导入预设列表
- **RoutingSettingActivity / RoutingEditActivity**：规则集列表 + 域名策略 + 预设导入；规则编辑（域名/IP/进程 via AppPickerActivity + 出站标签建议）
- **SubSettingActivity / SubEditActivity**：增删改排序、批量更新、QR 分享；订阅字段含 prev/next profile、allowInsecureUrl
- **UserAssetActivity**：本地文件/URL/二维码/自动下载，地源镜像选择
- **BackupActivity**：上游本地 ZIP（`MMKV.restoreAllFromDirectory`）+ WebDAV 远程；Hey 当前无云服务器，备份能力不进入现阶段复刻验收

## 6. 便捷功能清单（`MainActivity.kt` + `menu_main.xml`）

| 功能 | 菜单项 | 方法 |
|------|------|------|
| 批量 TCping | ping_all | `testAllTcping()` |
| 批量 RealPing | real_ping_all | `testAllRealPing()` |
| 按延迟排序 | sort_by_test_results | `sortByTestResults()` |
| 导出全部 | export_all | `exportAllServer()` |
| 清空全部 | del_all_config | `removeAllServer()` |
| 删除重复 | del_duplicate_config | `removeDuplicateServer()` |
| 删除无效 | del_invalid_config | `removeInvalidServer()` |
| 定位选中 | locate_selected_config | `locateSelectedServer()` |

导入方式：扫码、剪贴板、本地文件、手动创建各协议（vmess/vless/ss/socks/http/trojan/wireguard/hysteria2）、策略组、代理链、订阅更新。

导航菜单（`menu_drawer.xml`）：订阅、分应用代理、路由、资源、设置 + 推广、日志、检查更新、备份、关于；其中备份仅作 v2rayNG 上游记录，Hey 当前不实现。

## 7. ViewModel 架构

`MainViewModel`（`viewmodel/MainViewModel.kt:41-300+`）核心数据：subscriptionId、serversCache、isRunning、updateListAction、updateTestResultAction。
方法：reloadServerList、removeServer、swapServer、filterConfig、testAllTcping/RealPing、sortByTestResults、removeDuplicate/InvalidServer、exportAllServer、updateConfigViaSubAll。

其他：PerAppProxyViewModel、RoutingSettingsViewModel、SubscriptionsViewModel、UserAssetViewModel、LogcatViewModel。

## 8. 技术架构亮点

MMKV 存储、MVVM（LiveData + ViewModel 生命周期感知）、Coroutine（IO/Main 切换）、ItemTouchHelper 拖拽、ActivityResultContract、RecyclerView、ViewPager2、SearchView 实时过滤、AlertDialog 确认。

## 9. 关键交互流程

```
添加：MainMenu → ScannerActivity → importBatchConfig → 解析 → encodeServerConfig → 刷新列表
选择：点击节点 → setSelectServer → 运行中则 restartV2Ray(stop→start)
编辑：编辑按钮 → ServerActivity/Custom/Group → 校验 → encodeServerConfig → reload
分享：分享按钮 → AlertDialog(QR/剪贴板/完整 JSON/编辑/删除)
订阅更新：updateConfigViaSubAll → 遍历订阅 → HTTP 获取 → 解析保存 → 更新时间戳 → reload
```

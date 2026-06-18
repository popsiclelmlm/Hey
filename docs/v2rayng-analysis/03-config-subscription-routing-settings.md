# v2rayNG 配置管理 / 订阅 / 路由 / 设置

> 领域三：MMKV 存储模型、订阅自动更新、路由规则集与负载均衡、设置项全表、WebDAV、geo 资产。
> 代码位置基于 v2rayNG 源码（`app/src/main/java/com/v2ray/ang`）。

## 1. 服务器配置存储（MMKV）

`handler/MmkvManager.kt` 全局单例，多实例分离存储：

| MMKV ID | 用途 | 内容 |
|---------|------|------|
| MAIN | 主存储 | 选中服务器 GUID、订阅 ID 列表、WebDAV 配置 |
| PROFILE_FULL_CONFIG | 完整配置 | ProfileItem JSON（按 GUID） |
| SERVER_RAW | 原始配置 | 自定义配置原始 JSON |
| SERVER_AFF | 关联信息 | 测速延迟 testDelayMillis |
| SUB | 订阅 | SubscriptionItem JSON（按订阅 ID） |
| ASSET | 资源 URL | AssetUrlItem JSON |
| SETTING | 设置 | DNS/MTU/Mux 等偏好 |

`ProfileItem`（`dto/entities/ProfileItem.kt:7-78`）核心字段：configType、subscriptionId、remarks、server/serverPort、password/username/method、network、security、sni/alpn、fingerPrint、publicKey/shortId（Reality）、secretKey/preSharedKey（WireGuard）、policyGroupType/policyGroupSubscriptionId（负载均衡）、bandwidthDown/Up。

## 2. 订阅（Subscription）

`SubscriptionItem`（`dto/entities/SubscriptionItem.kt`）：remarks、url、enabled、autoUpdate、updateInterval（分钟，默认 1440）、lastUpdated、filter（正则）、allowInsecureUrl、userAgent。

### 2.1 自动更新（`handler/SubscriptionUpdater.kt`）

- 基于 AndroidX **WorkManager** PeriodicWork，每订阅一个独立任务 `subscription_updater_${subId}`
- 约束 `NetworkType.CONNECTED`，最小间隔 15 分钟
- `sync()`（`:36-59`）应用启动时同步全部；`syncOne()`（`:65-73`）编辑后同步；`cancelOne()`（`:79-82`）取消
- `UpdateTask.doWork()`（`:150-192`）→ `AngConfigManager.updateConfigViaSub()`

### 2.2 更新过程（`AngConfigManager.kt`）

`updateConfigViaSub()`（`:527-606`）：校验启用 → 取 httpPort 经代理下载 → 自定义 UA → 更新 lastUpdated → 返回结果统计。
`updateConfigViaSubAll()`（`:509-519`）更新全部。
数据流：HTTP 下载 → Base64 解码 → 逐行解析协议 URL/JSON → 应用 filter 正则 → 批量保存。

### 2.3 分组

每订阅独立 serverList（GUID 数组），键 `SUB_SERVERS_${id}`；默认订阅 `__default_subscription__` 收纳未指定订阅的服务器。

> 注：当前版本未直接解析订阅协议中的流量信息（到期/已用流量），`bandwidthDown/Up` 为限速字段，需手动设置。

## 3. 路由（Routing）

`enums/RoutingType.kt`：WHITE（白名单）/ BLACK（黑名单）/ GLOBAL / WHITE_IRAN / WHITE_RUSSIA，各对应一个 assets 文件。

### 3.1 自定义规则集

`RulesetItem`（`dto/entities/RulesetItem.kt:3-14`）：remarks、ip、domain、process、outboundTag、port、network、protocol、enabled、locked。
存储键 `PREF_ROUTING_RULESET`，JSON 数组存于 MMKV SETTING；`MmkvManager.decodeRoutingRulesets()/encodeRoutingRulesets()`。

### 3.2 预设规则集（`handler/SettingsManager.kt:55-127`）

启动时从 `assets/${RoutingType.fileName}` 加载。操作接口：`getRoutingRuleset/saveRoutingRuleset/removeRoutingRuleset/swapRoutingRuleset/resetRoutingRulesetsFromPresets/resetRoutingRulesets`。

### 3.3 绕过局域网（`SettingsManager.kt:182-206`）

`routingRulesetsBypassLan()`：查 direct 规则是否含 `geosite:private`/`geoip:private`；`PREF_VPN_BYPASS_LAN`："0" 跟随配置 / "1" 绕过 LAN / "2" 不绕过 LAN。

### 3.4 负载均衡（`enums/BalancerStrategyType.kt`）

| 策略 | policyGroupType | 备注 |
|------|----------------|------|
| LEAST_LOAD | leastLoad | 需 burstObservatory |
| RANDOM | random | — |
| ROUND_ROBIN | roundRobin | — |
| LEAST_PING | leastPing | 默认，需 observatory |

ProfileItem 中 `policyGroupType` + `policyGroupSubscriptionId` + `policyGroupFilter`：从指定订阅按正则选成员，应用策略。

## 4. 设置项全表（`handler/SettingsManager.kt`）

### 网络
| 项 | Key | 默认 |
|---|---|---|
| SOCKS 端口 | `PREF_SOCKS_PORT` | 10808 |
| 动态 SOCKS 端口 | `PREF_DYNAMIC_SOCKS_PORT` | false |
| SOCKS 账号/密码/UDP | `PREF_SOCKS_USERNAME/PASSWORD/ENABLE_UDP` | — |

`getSocksPort()`（`:289-297`）动态端口时返回运行时随机端口；`getHttpPort()` = SOCKS+（Xray?0:1）。

### DNS
| 项 | Key | 默认 |
|---|---|---|
| VPN DNS | `PREF_VPN_DNS` | 1.1.1.1 |
| 远程 DNS | `PREF_REMOTE_DNS` | 1.1.1.1 |
| 国内 DNS | `PREF_DOMESTIC_DNS` | 223.5.5.5 |
| 本地 DNS 端口 | `PREF_LOCAL_DNS_PORT` | 10853 |
| 本地/Fake DNS 启用 | `PREF_LOCAL_DNS_ENABLED`/`PREF_FAKE_DNS_ENABLED` | — |
| 自定义 hosts | `PREF_DNS_HOSTS` | — |

### Mux
`PREF_MUX_ENABLED` / `PREF_MUX_CONCURRENCY`(8) / `PREF_MUX_XUDP_CONCURRENCY`(8) / `PREF_MUX_XUDP_QUIC`。

### Fragment（分片）
`PREF_FRAGMENT_ENABLED` / `PREF_FRAGMENT_PACKETS` / `PREF_FRAGMENT_LENGTH`(50-100) / `PREF_FRAGMENT_INTERVAL`(10-20)。

### VPN
| 项 | Key | 默认 |
|---|---|---|
| 模式 | `PREF_MODE` | VPN |
| MTU | `PREF_VPN_MTU` | 1500 |
| 接口地址方案 | `PREF_VPN_INTERFACE_ADDRESS_CONFIG_INDEX` | 0 |
| 绕过 LAN | `PREF_VPN_BYPASS_LAN` | 1 |
| HEV Tunnel | `PREF_USE_HEV_TUNNEL` | true |
| HEV 读写超时 | `PREF_HEV_TUNNEL_RW_TIMEOUT` | 300,60 |

### 延迟测试
`PREF_DELAY_TEST_URL`(gstatic generate_204) / `PREF_IP_API_URL`(api.ip.sb/geoip) / `PREF_REAL_PING_CONCURRENCY`(16,范围1-128)。

### 其他
本地代理、代理共享、分应用代理、应用绕过列表、语言、夜间模式、速度通知、检查更新（含预发布）、日志等级、`PREF_AUTO_REMOVE_INVALID_AFTER_TEST`、`PREF_AUTO_SORT_AFTER_TEST`、Sniffing、route-only。

`ensureDefaultSettings()`（`:515-536`）启动时保证默认值。

## 5. WebDAV 云备份（`handler/WebDavManager.kt`）

`WebDavConfig(baseUrl, username, password, remoteBasePath="/", timeoutSeconds=30)`，存于 MMKV MAIN。
- `init()`（`:27-35`）：OkHttpClient + 超时 + 认证
- `uploadFile()`（`:46-80`）：自动 `ensureRemoteDirs`（递归 MKCOL，忽略 405/409），按扩展名设 Content-Type
- `downloadFile()`（`:89-114`）
- `applyAuth()`（`:142-149`）：`Credentials.basic()` HTTP BASIC
- 备份目录 `backups`，文件名 `backup_ng.zip`

## 6. Geo 资产管理

资产类型：geosite.dat、geoip.dat、geoip-only-cn-private.dat。存于 `Utils.userAssetPath(context)`。
- `initAssets()`（`SettingsManager.kt:337-357`）启动时从 APK assets 复制（仅复制不存在的，不覆盖已更新）
- `AssetUrlItem`（remarks/url/addedTime/lastUpdated/locked），存于 MMKV ASSET
- 来源配置 `PREF_GEO_FILES_SOURCES`：github(官方) / loyalsoldier(geoip) / daycat(geosite)
- 路由引用：`geosite:cn`、`geoip:cn`、`geosite:private`、`geoip:private`、`ext:geoip-only-cn-private.dat:cn`

## 7. 其他管理器

| 管理器 | 文件 | 职责 |
|--------|------|------|
| 测速 | `handler/SpeedtestManager.kt` | `tcping()`、`socketConnectTime()`、`getRemoteIPInfo()`、`closeAllTcpSockets()` |
| 通知 | `handler/NotificationManager.kt` | 前台通知（启停/重启按钮）、速度通知（3 秒刷新） |
| 更新检查 | `handler/UpdateCheckerManager.kt` | GitHub API 比对版本、按 ABI 选 APK、区分 F-Droid/Play |
| 设置变更 | `handler/SettingsChangeManager.kt` | StateFlow 标记 restartService / setupGroupTab |

## 8. 迁移机制（`SettingsManager.kt`）

`initApp()`（`:43-49`）：`ensureDefaultSettings` + `initRoutingRulesets` + `migrateServerListToSubscriptions`（`:570-611` 旧服务器迁入订阅系统）+ `migrateHysteria2PinSHA256`（`:538-561` pinSHA256→pinnedCA256）。

## 9. 数据流示意

```
订阅 URL → HttpUtil.getUrlContent(经代理) → Base64 解码 → 逐行解析
  ├ VmessFmt / VlessFmt / TrojanFmt / ShadowsocksFmt / WireguardFmt / CustomFmt
  → 应用 filter 正则 → 生成 ProfileItem(setSubscriptionId)
  → MMKV profileFullStorage(按 GUID) → 更新订阅 serverList → 持久化 mainStorage
  → SubscriptionItem.lastUpdated = now
```

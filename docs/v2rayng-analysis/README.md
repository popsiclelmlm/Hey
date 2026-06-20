# v2rayNG 源码分析（参考资料）

本目录是对 Android 开源代理应用 **v2rayNG** 的功能、能力与设计思路的体系化分析，
作为 Hey（HarmonyOS Next）开发的对标参考。分析基于 v2rayNG 真实源码
（参考仓库 <https://github.com/2dust/v2rayNG>），按四个功能领域拆分

## 文档索引

| 文档 | 领域 | 内容概要 |
| --- | --- | --- |
| [01-protocols-and-parsing.md](01-protocols-and-parsing.md) | 协议支持与配置解析 | 10 种协议、传输方式、安全层、分享链接格式、Reality/flow/mux 等高级特性、`FmtBase` 抽象 |
| [02-core-engine-and-services.md](02-core-engine-and-services.md) | 核心引擎与系统服务 | Xray 核心启停、VPN/TUN、仅代理模式、QSTile/Widget/Tasker/URL Scheme、测速、DNS/分应用/路由 |
| [03-config-subscription-routing-settings.md](03-config-subscription-routing-settings.md) | 配置管理/订阅/路由/设置 | MMKV 存储、订阅自动更新、路由规则集与负载均衡、设置项全表、WebDAV 上游参考（Hey 当前不做备份）、geo 资产 |
| [04-ui-and-features.md](04-ui-and-features.md) | 用户界面与功能交互 | 全部 Activity 清单、主界面交互、服务器编辑、扫码/分享、批量便捷功能、ViewModel 架构 |

## 配套文档

- [`../development-plan.md`](../development-plan.md) — Hey 未来开发计划（基于本分析对标制定）
- [`../v2rayng-feature-map.md`](../v2rayng-feature-map.md) — 页面/功能对照表（Hey vs v2rayNG）
- [`../roadmap.md`](../roadmap.md) — 早期完成度评估

---
生成日期：2026-06-05

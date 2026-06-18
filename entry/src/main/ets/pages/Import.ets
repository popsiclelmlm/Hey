import { common } from '@kit.AbilityKit';
import { router, promptAction } from '@kit.ArkUI';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage } from '../core/Profile';
import { NODES_CONTROLLER } from '../features/nodes/NodesController';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { AppRoute } from '../shell/AppRoute';
import { SectionHeader } from '../components/SectionHeader';
import { PageHeader } from '../shell/PageHeader';
import { SubscriptionStore } from '../storage/SubscriptionStore';
import { convertNativeShareTextToOutbounds } from '../services/NativeShareConverter';
import { AppColor, FontSz, Radius, Space } from '../theme/Theme';

@Entry
@Component
struct ImportPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private importBuffer: string = '';
  @State private lastError: string = '';
  @State private isBusy: boolean = false;

  aboutToAppear(): void {
    this.loadState();
  }

  build() {
    Column() {
      PageHeader({
        title: this.t('screen.import.title'),
        showBack: true
      })
      Scroll() {
        Column({ space: Space.lg }) {
          // 模块一：解析协议链接 / 扫码
          this.LinkImportSection()

          // 模块二：手动协议配置
          this.ManualGridSection()

          // 模块三：高级出站配置
          this.AdvancedConfigSection()

          // 模块四：自定义 JSON 配置
          this.JsonImportSection()

          if (this.lastError.length > 0) {
            Text(this.lastError)
              .fontSize(FontSz.footnote)
              .fontColor(AppColor.danger)
              .width('100%')
              .padding(Space.md)
              .backgroundColor(AppColor.dangerTint)
              .borderRadius(Radius.md)
              .margin({ left: Space.lg, right: Space.lg })
          }
        }
        .width('100%')
        .padding({ top: Space.sm, bottom: Space.xxl })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .height('100%')
    .width('100%')
    .backgroundColor(AppColor.bg)
  }

  @Builder
  private RowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color(AppColor.divider)
      .margin({ left: Space.lg })
  }

  // 1. 扫码与链接导入区
  @Builder
  private LinkImportSection() {
    SectionHeader({ title: '扫码与链接导入' })
    Column() {
      Row() {
        Image($r('app.media.ic_link'))
          .width(20)
          .height(20)
          .fillColor(AppColor.textSecondary)
          .margin({ left: Space.lg, right: Space.sm })

        TextInput({
          placeholder: '输入或粘贴节点连接 URL',
          text: this.importBuffer
        })
          .layoutWeight(1)
          .height(48)
          .fontSize(FontSz.body)
          .fontColor(AppColor.textPrimary)
          .placeholderColor(AppColor.textTertiary)
          .backgroundColor(Color.Transparent)
          .onChange((value: string) => {
            this.importBuffer = value;
          })

        if (this.importBuffer.length > 0) {
          Button() {
            Text('✕')
              .fontSize(FontSz.footnote)
              .fontColor(AppColor.textSecondary)
              .fontWeight(FontWeight.Bold)
          }
          .backgroundColor(AppColor.surfaceAlt)
          .width(28)
          .height(28)
          .borderRadius(14)
          .margin({ right: Space.md })
          .onClick(() => {
            this.importBuffer = '';
          })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor(AppColor.surface)
    .borderRadius(Radius.lg)
    .clip(true)
    .margin({ left: Space.lg, right: Space.lg })

    Text('粘贴分享链接（如 vless://, vmess://, ss://, trojan:// 等）或点击扫码解析。')
      .fontSize(FontSz.footnote)
      .fontColor(AppColor.textTertiary)
      .width('100%')
      .lineHeight(16)
      .padding({ left: Space.lg + Space.xs, right: Space.lg + Space.xs })

    Row({ space: Space.md }) {
      Button() {
        Row() {
          if (this.isBusy) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(AppColor.onBrand)
              .margin({ right: Space.xs + 2 })
          }
          Text('解析并导入')
            .fontSize(FontSz.callout)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.importBuffer.trim().length > 0 ? AppColor.onBrand : AppColor.textTertiary)
        }
      }
      .height(46)
      .layoutWeight(1)
      .enabled(!this.isBusy && this.importBuffer.trim().length > 0)
      .backgroundColor(this.importBuffer.trim().length > 0 ? AppColor.brand : AppColor.surfaceAlt)
      .borderRadius(Radius.pill)
      .onClick(() => {
        this.importLink();
      })

      Button() {
        Row({ space: Space.xs + 2 }) {
          Image($r('app.media.ic_qr_code'))
            .width(18)
            .height(18)
            .fillColor(AppColor.textSecondary)
          Text('扫码')
            .fontSize(FontSz.callout)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColor.textSecondary)
        }
      }
      .height(46)
      .padding({ left: Space.lg, right: Space.lg })
      .backgroundColor(AppColor.surfaceAlt)
      .borderRadius(Radius.pill)
      .onClick(() => {
        router.pushUrl({ url: AppRoute.SCANNER });
      })
    }
    .width('100%')
    .margin({ left: Space.lg, right: Space.lg })
  }

  // 2. 手动协议配置列表
  @Builder
  private ManualGridSection() {
    SectionHeader({ title: '手动配置节点' })
    Column() {
      this.ProtocolRow('vless')
      this.RowDivider()
      this.ProtocolRow('vmess')
      this.RowDivider()
      this.ProtocolRow('trojan')
      this.RowDivider()
      this.ProtocolRow('ss')
      this.RowDivider()
      this.ProtocolRow('socks')
      this.RowDivider()
      this.ProtocolRow('http')
      this.RowDivider()
      this.ProtocolRow('wireguard')
      this.RowDivider()
      this.ProtocolRow('hysteria2')
    }
    .width('100%')
    .backgroundColor(AppColor.surface)
    .borderRadius(Radius.lg)
    .clip(true)
    .margin({ left: Space.lg, right: Space.lg })
  }

  @Builder
  private ProtocolRow(protocol: string) {
    Row({ space: Space.md }) {
      Column({ space: 3 }) {
        Text(protocol === 'hysteria2' ? 'HY2' : protocol.toUpperCase())
          .fontSize(FontSz.callout)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textPrimary)
        Text(`${protocol === 'ss' ? 'Shadowsocks' : (protocol === 'wireguard' ? 'WireGuard' : (protocol === 'hysteria2' ? 'Hysteria 2' : protocol.toUpperCase()))} 协议`)
          .fontSize(FontSz.footnote)
          .fontColor(AppColor.textTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Image($r('app.media.ic_chevron_right'))
        .width(20)
        .height(20)
        .fillColor(AppColor.textTertiary)
    }
    .width('100%')
    .padding(Space.lg)
    .onClick(() => {
      router.pushUrl({
        url: AppRoute.NODE_EDIT,
        params: { protocol: protocol }
      })
    })
  }

  // 3. 代理链 / 策略组配置入口
  @Builder
  private AdvancedConfigSection() {
    SectionHeader({ title: '高级配置' })
    Column() {
      this.AdvancedOutboundRow(
        this.t('advancedOutbound.proxyChain'),
        this.t('advancedOutbound.proxyChain.detail'),
        'proxy-chain'
      )
      this.RowDivider()
      this.AdvancedOutboundRow(
        this.t('advancedOutbound.policyGroup'),
        this.t('advancedOutbound.policyGroup.detail'),
        'policy-group'
      )
    }
    .width('100%')
    .backgroundColor(AppColor.surface)
    .borderRadius(Radius.lg)
    .clip(true)
    .margin({ left: Space.lg, right: Space.lg })
  }

  @Builder
  private AdvancedOutboundRow(title: string, detail: string, mode: string) {
    Row({ space: Space.md }) {
      Image($r('app.media.ic_route'))
        .width(20)
        .height(20)
        .fillColor(AppColor.brand)

      Column({ space: 3 }) {
        Text(title)
          .fontSize(FontSz.callout)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textPrimary)
        Text(detail)
          .fontSize(FontSz.footnote)
          .fontColor(AppColor.textTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Image($r('app.media.ic_chevron_right'))
        .width(20)
        .height(20)
        .fillColor(AppColor.textTertiary)
    }
    .width('100%')
    .padding(Space.lg)
    .onClick(() => {
      router.pushUrl({
        url: AppRoute.ADVANCED_OUTBOUND,
        params: { mode: mode }
      })
    })
  }

  // 4. 自定义 JSON 导入入口
  @Builder
  private JsonImportSection() {
    SectionHeader({ title: '自定义配置' })
    Column() {
      Row({ space: Space.md }) {
        Column({ space: 3 }) {
          Text('导入 JSON 配置')
            .fontSize(FontSz.callout)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColor.textPrimary)
          Text('粘贴或选择文件导入 Xray outbound JSON / 完整配置。')
            .fontSize(FontSz.footnote)
            .fontColor(AppColor.textTertiary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Image($r('app.media.ic_chevron_right'))
          .width(20)
          .height(20)
          .fillColor(AppColor.textTertiary)
      }
      .width('100%')
      .padding(Space.lg)
      .onClick(() => {
        router.pushUrl({ url: AppRoute.JSON_IMPORT });
      })
    }
    .width('100%')
    .backgroundColor(AppColor.surface)
    .borderRadius(Radius.lg)
    .clip(true)
    .margin({ left: Space.lg, right: Space.lg })
  }

  private async loadState(): Promise<void> {
    try {
      const context = getContext(this) as common.Context;
      this.language = (await SETTINGS_CONTROLLER.load(context)).language;
    } catch (error) {
      this.lastError = '加载页面配置失败：' + JSON.stringify(error);
    }
  }

  private async importLink(): Promise<void> {
    const value = this.importBuffer.trim();
    if (value.length === 0) {
      this.lastError = this.t('error.emptyImport');
      return;
    }

    this.isBusy = true;
    try {
      const context = getContext(this) as common.Context;
      if (value.toLowerCase().startsWith('http://') || value.toLowerCase().startsWith('https://')) {
        this.lastError = this.t('error.importSubscriptionNotAllowed');
        return;
      }

      const saved = await NODES_CONTROLLER.saveProfile(context, value, this.language);
      if (saved.profile === null) {
        const nativeResult = convertNativeShareTextToOutbounds(value);
        if (!nativeResult.ok) {
          this.lastError = nativeResult.message.length > 0 ? `${saved.lastError}\n${nativeResult.message}` : saved.lastError;
          return;
        }

        let importedCount = 0;
        let lastValidationError = '';
        for (let index = 0; index < nativeResult.outbounds.length; index++) {
          const outbound = nativeResult.outbounds[index];
          const imported = await NODES_CONTROLLER.saveProfile(context, outbound.outboundJson, this.language, 'outbound');
          if (imported.profile === null) {
            lastValidationError = imported.lastError;
            continue;
          }
          await SubscriptionStore.addManualNode(
            context,
            this.resolveNodeName(imported.profile.outboundJson, outbound.name),
            imported.profile.outboundJson,
            imported.profile.configType
          );
          importedCount++;
        }

        if (importedCount === 0) {
          this.lastError = lastValidationError.length > 0 ? lastValidationError : saved.lastError;
          return;
        }

        promptAction.showToast({ message: importedCount === 1 ? '节点解析成功' : `已导入 ${importedCount} 个节点` });
        router.back();
        return;
      }

      const nodeName = this.resolveNodeName(saved.profile.outboundJson, '链接导入');
      await SubscriptionStore.addManualNode(context, nodeName, saved.profile.outboundJson, saved.profile.configType);
      promptAction.showToast({ message: '节点解析成功' });
      router.back();
    } catch (error) {
      this.lastError = '解析失败：' + JSON.stringify(error);
    } finally {
      this.isBusy = false;
    }
  }

  private resolveNodeName(outboundJson: string, fallback: string): string {
    let nodeName = fallback.trim().length > 0 ? fallback.trim() : '链接导入';
    try {
      const obj = JSON.parse(outboundJson) as Record<string, Object>;
      if (obj.tag && typeof obj.tag === 'string' && obj.tag.trim().length > 0) {
        nodeName = obj.tag.trim();
      } else if (obj.remarks && typeof obj.remarks === 'string' && obj.remarks.trim().length > 0) {
        nodeName = obj.remarks.trim();
      } else if (obj.name && typeof obj.name === 'string' && obj.name.trim().length > 0) {
        nodeName = obj.name.trim();
      }
    } catch (err) {
      // Keep fallback.
    }
    return nodeName;
  }

  private t(key: string): string {
    return translate(this.language, key);
  }
}

import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage, ProxyNode } from '../core/Profile';
import { NODES_CONTROLLER } from '../features/nodes/NodesController';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { PageHeader } from '../shell/PageHeader';
import { formatOne } from '../utils/LocalizationPresenter';

interface NodeDetailParams {
  nodeId?: string;
}

const EMPTY_NODE: ProxyNode = {
  id: '',
  name: '',
  protocol: '',
  outboundJson: '',
  sourceUrl: '',
  rawLink: '',
  updatedAt: 0,
  delayMs: -1,
  delayTestAt: 0,
  delayStatus: ''
};

@Entry
@Component
struct NodeDetailPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private nodeId: string = '';
  @State private node: ProxyNode = EMPTY_NODE;
  @State private selectedNodeId: string = '';
  @State private lastError: string = '';

  aboutToAppear(): void {
    this.loadState();
  }

  build() {
    Column() {
      PageHeader({
        title: this.t('node.detail.title'),
        summary: this.node.name,
        showBack: true
      })
      Scroll() {
        Column({ space: 12 }) {
          Text(this.node.name.length > 0 ? this.node.name : this.t('node.detail.missing'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#111827')
            .width('100%')
          Text(`${this.node.protocol.toUpperCase()}  ${this.node.sourceUrl.length > 0 ? this.t('node.source.subscription') : this.t('node.source.manual')}`)
            .fontSize(12)
            .fontColor('#6B7280')
            .width('100%')

          Row({ space: 8 }) {
            Button(this.node.id === this.selectedNodeId ? this.t('action.current') : this.t('action.use'))
              .height(40)
              .layoutWeight(1)
              .enabled(this.node.id.length > 0 && !SHARED_RUNTIME_CONTROLLER.isBusy())
              .backgroundColor(this.node.id === this.selectedNodeId ? '#166534' : '#1D4ED8')
              .fontColor('#FFFFFF')
              .borderRadius(8)
              .onClick(() => {
                this.selectNode();
              })
            Button(this.t('action.del'))
              .height(40)
              .width(82)
              .enabled(this.node.id.length > 0)
              .backgroundColor('#B42318')
              .fontColor('#FFFFFF')
              .borderRadius(8)
              .onClick(() => {
                this.removeNode();
              })
          }
          .width('100%')

          if (this.lastError.length > 0) {
            Text(this.lastError)
              .fontSize(12)
              .fontColor('#B42318')
              .width('100%')
              .padding(10)
              .backgroundColor('#FEF3F2')
              .borderRadius(6)
          }

          Text(this.t('node.detail.outbound'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#111827')
            .width('100%')
          TextArea({ text: this.node.outboundJson, placeholder: this.t('placeholder.outbound') })
            .height(280)
            .fontSize(12)
            .fontColor('#111827')
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
            .padding(10)

          if (this.node.rawLink.length > 0) {
            Text(this.t('node.detail.rawLink'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#111827')
              .width('100%')
            TextArea({ text: this.node.rawLink, placeholder: '' })
              .height(120)
              .fontSize(12)
              .fontColor('#111827')
              .backgroundColor('#FFFFFF')
              .borderRadius(8)
              .padding(10)
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 14, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .height('100%')
    .width('100%')
    .backgroundColor('#F6F8FA')
  }

  private async loadState(): Promise<void> {
    const params = router.getParams() as NodeDetailParams;
    if (params !== undefined && params.nodeId !== undefined) {
      this.nodeId = params.nodeId;
    }
    const context = getContext(this) as common.Context;
    this.language = (await SETTINGS_CONTROLLER.load(context)).language;
    const state = await NODES_CONTROLLER.load(context, this.language);
    this.selectedNodeId = state.selectedNodeId;
    const found = NODES_CONTROLLER.findNode(state.nodes, this.nodeId);
    this.node = found !== null ? found : EMPTY_NODE;
  }

  private async selectNode(): Promise<void> {
    if (this.node.id.length === 0) {
      return;
    }
    this.selectedNodeId = this.node.id;
    const context = getContext(this) as common.Context;
    const state = await NODES_CONTROLLER.selectNode(context, this.node, this.language);
    this.selectedNodeId = state.selectedNodeId;
    this.lastError = state.lastError;
    SHARED_RUNTIME_CONTROLLER.appendLog(state.lastError.length > 0 ? state.lastError : this.f1('log.selectedNode', 'name', this.node.name));
  }

  private async removeNode(): Promise<void> {
    if (this.node.id.length === 0) {
      return;
    }
    const context = getContext(this) as common.Context;
    await NODES_CONTROLLER.removeNode(context, this.node.id, this.language);
    SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.nodeRemoved', 'name', this.node.name));
    router.back();
  }

  private t(key: string): string {
    return translate(this.language, key);
  }

  private f1(key: string, name: string, value: string): string {
    return formatOne(this.language, key, name, value);
  }
}

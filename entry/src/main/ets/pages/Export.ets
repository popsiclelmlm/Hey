import { common } from '@kit.AbilityKit';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage, ProxyNode } from '../core/Profile';
import { buildNodeExportModel, NodeExportModel } from '../features/nodes/NodeOperations';
import { NODES_CONTROLLER } from '../features/nodes/NodesController';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { PageHeader } from '../shell/PageHeader';
import { formatOne } from '../utils/LocalizationPresenter';

@Entry
@Component
struct ExportPage {
  @State private language: AppLanguage = DEFAULT_LANGUAGE;
  @State private nodes: Array<ProxyNode> = [];
  @State private exportTitle: string = '';
  @State private exportContent: string = '';
  @State private exportCount: number = 0;

  aboutToAppear(): void {
    this.loadState();
  }

  build() {
    Column() {
      PageHeader({
        title: this.t('export.title'),
        summary: this.f1('export.summary', 'count', this.exportCount.toString()),
        showBack: true
      })
      Scroll() {
        Column({ space: 12 }) {
          Text(this.exportTitle)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#111827')
            .width('100%')

          TextArea({
            placeholder: this.t('export.empty'),
            text: this.exportContent
          })
            .height(420)
            .fontSize(12)
            .fontColor('#111827')
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
            .padding(10)
            .onChange((value: string) => {
              this.exportContent = value;
            })

          Text(this.t('export.copyHint'))
            .fontSize(12)
            .fontColor('#6B7280')
            .width('100%')
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
    const context = getContext(this) as common.Context;
    this.language = (await SETTINGS_CONTROLLER.load(context)).language;
    this.nodes = (await NODES_CONTROLLER.load(context, this.language)).nodes;
    const model: NodeExportModel = buildNodeExportModel(this.t('export.nodesTitle'), this.nodes);
    this.exportTitle = model.title;
    this.exportContent = model.content;
    this.exportCount = model.count;
    SHARED_RUNTIME_CONTROLLER.appendLog(this.f1('log.exportPrepared', 'count', this.exportCount.toString()));
  }

  private t(key: string): string {
    return translate(this.language, key);
  }

  private f1(key: string, name: string, value: string): string {
    return formatOne(this.language, key, name, value);
  }
}

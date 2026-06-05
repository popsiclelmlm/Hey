import { common } from '@kit.AbilityKit';
import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage, ProxyNode } from '../core/Profile';
import { buildNodeExportModel, NodeExportModel } from '../features/nodes/NodeOperations';
import { NODES_CONTROLLER } from '../features/nodes/NodesController';
import { SETTINGS_CONTROLLER } from '../features/settings/SettingsController';
import { SHARED_RUNTIME_CONTROLLER } from '../features/runtime/RuntimeController';
import { SectionHeader } from '../components/SectionHeader';
import { PageHeader } from '../shell/PageHeader';
import { formatOne } from '../utils/LocalizationPresenter';
import { AppColor, FontSz, Radius, Space } from '../theme/Theme';

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
        Column({ space: Space.lg }) {
          SectionHeader({ title: this.exportTitle })
          Column() {
            TextArea({
              placeholder: this.t('export.empty'),
              text: this.exportContent
            })
              .height(420)
              .width('100%')
              .fontSize(FontSz.footnote)
              .fontColor(AppColor.textPrimary)
              .fontFamily('monospace')
              .backgroundColor(Color.Transparent)
              .borderRadius(0)
              .padding(Space.lg)
              .onChange((value: string) => {
                this.exportContent = value;
              })
          }
          .width('100%')
          .backgroundColor(AppColor.surface)
          .borderRadius(Radius.lg)
          .clip(true)
          .margin({ left: Space.lg, right: Space.lg })

          Text(this.t('export.copyHint'))
            .fontSize(FontSz.footnote)
            .fontColor(AppColor.textTertiary)
            .width('100%')
            .padding({ left: Space.lg + Space.xs, right: Space.lg + Space.xs })
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

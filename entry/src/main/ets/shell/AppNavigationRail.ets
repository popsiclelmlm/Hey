import { DEFAULT_LANGUAGE, translate } from '../core/I18n';
import { AppLanguage } from '../core/Profile';
import { AppScreen, ScreenEntry } from './AppScreen';

@Component
export struct AppNavigationRail {
  @Link activeScreen: AppScreen;
  entries: Array<ScreenEntry> = [];
  language: AppLanguage = DEFAULT_LANGUAGE;
  brand: string = 'Hey';

  private label(entry: ScreenEntry): string {
    return translate(this.language, entry.labelKey);
  }

  build() {
    Column({ space: 8 }) {
      Text(this.brand)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 8 })

      ForEach(this.entries, (entry: ScreenEntry) => {
        Button(this.label(entry))
          .height(36)
          .width('100%')
          .fontSize(12)
          .fontColor(this.activeScreen === entry.id ? '#111827' : '#D1D5DB')
          .backgroundColor(this.activeScreen === entry.id ? '#FFFFFF' : '#111827')
          .borderRadius(6)
          .onClick(() => {
            this.activeScreen = entry.id;
          })
      }, (entry: ScreenEntry) => entry.id)
    }
    .height('100%')
    .width(92)
    .padding({ left: 10, right: 10, top: 18, bottom: 18 })
    .backgroundColor('#111827')
  }
}

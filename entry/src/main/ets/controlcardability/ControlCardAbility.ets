import { Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData } from '@kit.FormKit';
import { buildControlCardFormData } from '../core/ControlCard';

export default class ControlCardAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    return formBindingData.createFormBindingData(buildControlCardFormData());
  }

  onUpdateForm(formId: string): void {
  }

  onRemoveForm(formId: string): void {
  }
}

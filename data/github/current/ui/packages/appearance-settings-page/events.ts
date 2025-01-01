import type {ContrastSettingProps} from '@github-ui/appearance-settings/ContrastSetting'

type ContrastSettingEventDetail = Parameters<ContrastSettingProps['onChange']>[0]

export class ContrastSettingChangeEvent extends Event {
  declare detail: ContrastSettingEventDetail
  constructor(detail: ContrastSettingEventDetail) {
    super('ContrastSetting:change')
    this.detail = detail
  }
}

export class AppearanceFormElementChangeEvent extends Event {
  declare detail: ContrastSettingEventDetail
  constructor(detail: ContrastSettingEventDetail) {
    super('appearance-form-element:change')
    this.detail = detail
  }
}

declare global {
  interface WindowEventMap {
    'ContrastSetting:change': ContrastSettingChangeEvent
    'appearance-form-element:change': AppearanceFormElementChangeEvent
  }
}

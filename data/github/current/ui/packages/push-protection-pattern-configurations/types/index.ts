// eslint-disable-next-line no-restricted-imports
import type {BoolSetting} from '@github-ui/secret-scanning/types/settings'

export interface PatternOverride {
  id: string
  slug: string
  display_name: string
  alert_total: number
  false_positives: number
  blocks: number
  bypasses: number
  default_setting: BoolSetting
  inherited_setting: BoolSetting
  setting: BoolSetting
}

export interface PatternSetting {
  token_type: string
  push_protection_setting: BoolSetting
}

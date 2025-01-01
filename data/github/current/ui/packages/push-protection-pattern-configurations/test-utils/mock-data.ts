// eslint-disable-next-line no-restricted-imports
import {BoolSetting} from '@github-ui/secret-scanning/types/settings'
import type {PatternConfigsPageResponse} from '../routes/pattern-configs-page-route'

export function getPatternConfigsPageRoutePayload({
  patternsCount = 1,
  has_parent = true,
} = {}): PatternConfigsPageResponse {
  return {
    org: {
      login: 'github',
    },
    pattern_config: {
      number: 1,
      total_alerts: 1000,
      provider_pattern_overrides: Array.from({length: patternsCount}).map((_, i) => {
        return {
          id: `Pattern ${i}`,
          slug: `Pattern ${i}`,
          display_name: `Pattern ${i}`,
          alert_total: 0,
          false_positives: 0,
          blocks: 0,
          bypasses: 0,
          default_setting: BoolSetting.Enabled,
          inherited_setting: BoolSetting.Enabled,
          setting: BoolSetting.Enabled,
        }
      }),
      custom_pattern_overrides: Array.from({length: patternsCount}).map((_, i) => {
        return {
          id: `Pattern ${i}`,
          slug: `Pattern ${i}`,
          display_name: `Pattern ${i}`,
          alert_total: 0,
          false_positives: 0,
          blocks: 0,
          bypasses: 0,
          default_setting: BoolSetting.Enabled,
          inherited_setting: BoolSetting.Enabled,
          setting: BoolSetting.Enabled,
        }
      }),
      row_version: '1',
    },
    has_parent,
    security_settings_path: 'path',
  }
}

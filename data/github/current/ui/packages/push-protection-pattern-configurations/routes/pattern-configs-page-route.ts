import {mainQuery} from '@github-ui/react-core/future/main-query'
import {pushProtectionPatternConfigurationsAppBuilder} from '../config/app-builder'

import type {PatternOverride} from '../types'

export type PatternConfigsPageResponse = {
  org: {login: string}
  pattern_config: {
    number: number
    total_alerts: number
    provider_pattern_overrides: PatternOverride[]
    custom_pattern_overrides: PatternOverride[]
    row_version: string
  }
  has_parent: boolean
  security_settings_path: string
}

export const patternConfigsPageRoute = pushProtectionPatternConfigurationsAppBuilder.createQueryRouteConfig(
  'patternConfigsPageRoute',
  {
    path: '/organizations/:org/settings/security_analysis/pattern_configurations',
    queries: [mainQuery<PatternConfigsPageResponse>()],
  },
)

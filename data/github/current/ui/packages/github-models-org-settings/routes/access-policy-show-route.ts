import {mainQuery} from '@github-ui/react-core/future/main-query'
import {appBuilder} from '../config/app'
import type {AccessPolicyShowPayload} from '../types'

export const accessPolicyShow = appBuilder.createQueryRouteConfig('accessPolicyShow', {
  // Keep in sync with the `organization_settings_models_access_policy_path` route helper in Rails
  path: '/organizations/:org/settings/models/access-policy',
  queries: [mainQuery<AccessPolicyShowPayload>()],
})

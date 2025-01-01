import {mainQuery} from '@github-ui/react-core/future/main-query'

import {modelsByokSettingsAppBuilder} from '../../config/app-builder'
import type {CustomModelsIndexPayload} from '../../types'

export const customModelsIndexRoute = modelsByokSettingsAppBuilder.createQueryRouteConfig('customModelsIndexRoute', {
  path: '/organizations/:org/settings/custom-models',
  queries: [mainQuery<CustomModelsIndexPayload>()],
})

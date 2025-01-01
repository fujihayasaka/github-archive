import {mainQuery} from '@github-ui/react-core/future/main-query'

import {reactCoreExamplesAppBuilder} from '../config/app-builder'
import type {UserStatus} from '../data-types'

type SharedComponentsPayload = {
  userStatus?: UserStatus
}

export const reactCoreExamplesSharedComponentsRoute = reactCoreExamplesAppBuilder.createQueryRouteConfig(
  'reactCoreExamplesSharedComponentsRoute',
  {
    path: '/_react_core_examples/shared_components',
    queries: [mainQuery<SharedComponentsPayload>()],
  },
)

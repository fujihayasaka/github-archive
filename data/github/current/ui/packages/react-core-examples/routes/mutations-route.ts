import {mainQuery} from '@github-ui/react-core/future/main-query'

import {reactCoreExamplesAppBuilder} from '../config/app-builder'

type MutationsPayload = {
  userStatus?: {
    emoji: string
    expiresAt: string
    limitedAvailability: boolean
    message: string
  }
}

export const reactCoreExamplesMutationsRoute = reactCoreExamplesAppBuilder.createQueryRouteConfig(
  'reactCoreExamplesMutationsRoute',
  {
    path: '/_react_core_examples/mutations',
    queries: [mainQuery<MutationsPayload>()],
  },
)

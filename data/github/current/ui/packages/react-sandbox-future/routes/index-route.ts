import {mainQuery} from '@github-ui/react-core/future/main-query'

import {reactSandboxFutureAppBuilder} from '../config/app-builder'

export const reactSandboxFutureIndexRoute = reactSandboxFutureAppBuilder.createQueryRouteConfig(
  'reactSandboxFutureIndexRoute',
  {
    path: '/_react_sandbox_future',
    index: true,
    queries: [mainQuery<{someField: string; serverTime: string}>()],
  },
)

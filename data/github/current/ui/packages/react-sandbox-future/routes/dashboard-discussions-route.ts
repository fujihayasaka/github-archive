import {mainQuery} from '@github-ui/react-core/future/main-query'

import {reactSandboxFutureAppBuilder} from '../config/app-builder'

type DashboardDiscussionsPayload = {
  open: number
  closed: number
}

export const reactSandboxFutureDashboardDiscussionsRoute = reactSandboxFutureAppBuilder.createQueryRouteConfig(
  'reactSandboxFutureDashboardDiscussionsRoute',
  {
    path: '/_react_sandbox_future/dashboard/discussions',
    queries: [mainQuery<DashboardDiscussionsPayload>()],
  },
)

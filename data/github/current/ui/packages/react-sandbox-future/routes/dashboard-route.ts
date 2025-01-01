import {mainQuery} from '@github-ui/react-core/future/main-query'
import {queryFnFetch} from '@github-ui/react-core/future/query-fn-fetch'

import {reactSandboxFutureAppBuilder} from '../config/app-builder'

type DashboardPayload = {
  user: string
}

type DashboardDeferredPayload = {
  tabCounts: {
    openIssues: number
    openPulls: number
    openDiscussions?: number
  }
}

export const reactSandboxFutureDashboardRoute = reactSandboxFutureAppBuilder.createQueryRouteConfig(
  'reactSandboxFutureDashboardRoute',
  {
    path: '/_react_sandbox_future/dashboard',
    queries: [
      mainQuery<DashboardPayload>({queryDeps: ({pathname}) => ({pathname}), staleTimeForNavigation: 360000}),
      {
        queryName: 'deferredPayload',
        queryDeps: () => {
          return {pathname: `/_react_sandbox_future/dashboard/deferred`}
        },
        queryFn: async queryKey => queryFnFetch<DashboardDeferredPayload>(queryKey),
      },
    ],
  },
)

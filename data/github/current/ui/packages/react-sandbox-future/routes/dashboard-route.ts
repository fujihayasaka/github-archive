import {mainQuery} from '@github-ui/react-core/future/query-configs'
import {reactSandboxFutureAppBuilder} from '../config/app-builder'
import {queryFnFetch} from '@github-ui/react-core/future/query-fn-fetch'
import {QueryRouteQueryType} from '@github-ui/react-core/future/data-router-types'

type DashboardPayload = {
  user: string
}

type DashboardDeferredPayload = {
  tabCounts: {
    openIssues: number
    openPulls: number
  }
}

export const reactSandboxFutureDashboardRoute = reactSandboxFutureAppBuilder.createQueryRouteConfig(
  'reactSandboxFutureDashboardRoute',
  {
    path: '/_react_sandbox_future/dashboard',
    queries: [
      mainQuery<DashboardPayload>({queryDeps: ({pathname}) => ({pathname})}),
      {
        queryName: 'deferredPayload',
        queryDeps: () => {
          return {pathname: `/_react_sandbox_future/dashboard/deferred`}
        },
        queryFn: async queryKey => queryFnFetch<DashboardDeferredPayload>(queryKey),
        type: QueryRouteQueryType.Deferred,
      },
    ],
  },
)

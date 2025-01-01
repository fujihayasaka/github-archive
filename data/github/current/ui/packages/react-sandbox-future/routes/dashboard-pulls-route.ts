import {mainQuery} from '@github-ui/react-core/future/query-configs'
import {reactSandboxFutureAppBuilder} from '../config/app-builder'
import {QueryRouteQueryType} from '@github-ui/react-core/future/data-router-types'
import {queryFnFetch} from '@github-ui/react-core/future/query-fn-fetch'
import type {DashboardIssue} from '../data-types'

type DashboardPullsPayload = {
  open: number
  closed: number
}

export type DashboardPullsDeferredPayload = {
  pulls: DashboardIssue[]
}

export const reactSandboxFutureDashboardPullsRoute = reactSandboxFutureAppBuilder.createQueryRouteConfig(
  'reactSandboxFutureDashboardPullsRoute',
  {
    path: '/_react_sandbox_future/dashboard/pulls',
    queries: [
      mainQuery<DashboardPullsPayload>({queryDeps: ({pathname}) => ({pathname})}),
      {
        queryName: 'deferredPulls',
        queryDeps: ({pathname, searchParams}) => ({
          pathname: `${pathname}/deferred`,
          searchParams: {state: searchParams.get('state')},
        }),
        queryFn: async queryKey => queryFnFetch<DashboardPullsDeferredPayload>(queryKey),
        type: QueryRouteQueryType.Deferred,
      },
    ],
  },
)

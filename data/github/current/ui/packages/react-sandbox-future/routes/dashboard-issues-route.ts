import {mainQuery} from '@github-ui/react-core/future/main-query'
import {queryFnFetch} from '@github-ui/react-core/future/query-fn-fetch'

import {reactSandboxFutureAppBuilder} from '../config/app-builder'
import type {DashboardIssue} from '../data-types'

type DashboardIssuesPayload = {
  open: number
  closed: number
}

type DashboardIssuesDeferredPayload = {
  issues: DashboardIssue[]
}

export const reactSandboxFutureDashboardIssuesRoute = reactSandboxFutureAppBuilder.createQueryRouteConfig(
  'reactSandboxFutureDashboardIssuesRoute',
  {
    path: '/_react_sandbox_future/dashboard/issues',
    queries: [
      mainQuery<DashboardIssuesPayload>(),
      {
        queryName: 'deferredIssues',
        queryDeps: ({pathname, searchParams}) => ({
          pathname: `${pathname}/deferred`,
          searchParams: {state: searchParams.get('state') === 'closed' ? 'closed' : 'open'},
        }),
        queryFn: async queryKey => queryFnFetch<DashboardIssuesDeferredPayload>(queryKey),
      },
    ],
  },
)

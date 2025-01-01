import {mainQuery} from '@github-ui/react-core/future/main-query'
import {queryFnFetch} from '@github-ui/react-core/future/query-fn-fetch'

import {reactSandboxFutureAppBuilder} from '../config/app-builder'
import type {DashboardIssue} from '../data-types'

type DashboardPullsPayload = {
  open: number
  closed: number
  feedbackUrl: string
}

export type DashboardPullsDeferredPayload = {
  pulls: DashboardIssue[]
}

export const reactSandboxFutureDashboardPullsRoute = reactSandboxFutureAppBuilder.createQueryRouteConfig(
  'reactSandboxFutureDashboardPullsRoute',
  {
    path: '/_react_sandbox_future/dashboard/pulls',
    queries: [
      mainQuery<DashboardPullsPayload>(),
      {
        queryName: 'deferredPulls',
        queryDeps: ({pathname, searchParams}) => ({
          pathname: `${pathname}/deferred`,
          /***
           * Note this is potentially an anti-pattern and is here for demonstration purposes.
           * For a better implementation, see `deferredIssues` query in `dashboard-issues-route.ts` which restricts
           * the `state` value to a known set of values:
           * ```ts
           *   searchParams: {state: searchParams.get('state') === 'closed' ? 'closed' : 'open'}
           * ```
           * By not defining a fall-back `state` value here we end up with three possible states: `null`, "open", and
           * "closed". This means that the `null` results get cached separately from the "open" results, and we get
           * a loading state when switching between the two.
           * This code also allows for arbitrary 'state' values which could further vary the cache key.
           */
          searchParams: {state: searchParams.get('state')},
        }),
        queryFn: async queryKey => queryFnFetch<DashboardPullsDeferredPayload>(queryKey),
      },
    ],
  },
)

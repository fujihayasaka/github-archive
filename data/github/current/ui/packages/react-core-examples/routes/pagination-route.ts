import {mainQuery} from '@github-ui/react-core/future/main-query'
import {queryFnFetch} from '@github-ui/react-core/future/query-fn-fetch'

import {reactCoreExamplesAppBuilder} from '../config/app-builder'
import type {Issue} from '../data-types'

export type PaginationPayload = {
  login: string
  count: number
}

export type DeferredPaginationPayload = {
  issues: Issue[]
}

export const reactCoreExamplesPaginationRoute = reactCoreExamplesAppBuilder.createQueryRouteConfig(
  'reactCoreExamplesPaginationRoute',
  {
    path: '/_react_core_examples/pagination',
    queries: [
      mainQuery<PaginationPayload>(),
      {
        queryName: 'deferredIssues',
        queryDeps: ({pathname, searchParams}) => ({
          pathname: `${pathname}/deferred`,
          searchParams: {
            page: searchParams.get('page') || '1',
          },
        }),
        queryFn: async queryKey => queryFnFetch<DeferredPaginationPayload>(queryKey),
      },
    ],
  },
)

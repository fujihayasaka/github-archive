import {queryFnFetch} from '@github-ui/react-core/future/query-fn-fetch'
import {pullRequestsAppBuilder} from '../config/app-builder'
import type {NavigationCounterPageData} from '../page-data/payloads/tab-counts'
import {mainQuery} from '@github-ui/react-core/future/main-query'
import type {LayoutRoutePayload} from './route-payload-types'

export const pullRequestsLayoutRoute = pullRequestsAppBuilder.createQueryRouteConfig('pullRequestsLayoutRoute', {
  path: '/:owner/:repo/pull/:pr_number',
  queries: [
    mainQuery<LayoutRoutePayload>(),
    {
      queryName: 'tabCounts',
      queryDeps: ({params}) => {
        return {pathname: `/${params.owner}/${params.repo}/pull/${params.pr_number}/page_data/tab_counts`}
      },
      queryFn: async queryKey => queryFnFetch<NavigationCounterPageData>(queryKey),
    },
  ],
})

import {pullRequestsAppBuilder} from '../config/app-builder'
import type {CommitsRoutePayload} from './Commits'
import {QueryRouteQueryType} from '@github-ui/react-core/future/data-router-types'
import type {NavigationCounterPageData} from '../page-data/payloads/tab-counts'
import {mainQuery} from '@github-ui/react-core/future/query-configs'
import {queryFnFetch} from '@github-ui/react-core/future/query-fn-fetch'

export const pullRequestsCommitsRoute = pullRequestsAppBuilder.createQueryRouteConfig('pullRequestsCommitsRoute', {
  path: '/:owner/:repo/pull/:pr_number/commits',
  queries: [
    mainQuery<CommitsRoutePayload>({queryDeps: ({pathname}) => ({pathname})}),
    {
      queryName: 'tabCounts',
      queryDeps: ({params}) => {
        return {pathname: `/${params.owner}/${params.repo}/pull/${params.pr_number}/page_data/tab_counts`}
      },
      queryFn: async queryKey => queryFnFetch<NavigationCounterPageData>(queryKey),
      type: QueryRouteQueryType.Deferred,
    },
  ],
})

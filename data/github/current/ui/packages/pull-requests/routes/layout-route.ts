import {pullRequestsAppBuilder} from '../config/app-builder'

export const pullRequestsLayoutRoute = pullRequestsAppBuilder.createQueryRouteConfig('pullRequestsLayoutRoute', {
  path: '/:owner/:repo/pull/:pr_number',
  queries: [],
})

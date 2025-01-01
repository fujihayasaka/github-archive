import {pullRequestsAppBuilder} from '../config/app-builder'
import {mainQuery} from '@github-ui/react-core/future/main-query'
import type {CommitsRoutePayload} from './route-payload-types'

export const pullRequestsCommitsRoute = pullRequestsAppBuilder.createQueryRouteConfig('pullRequestsCommitsRoute', {
  path: '/:owner/:repo/pull/:pr_number/commits',
  queries: [mainQuery<CommitsRoutePayload>()],
})

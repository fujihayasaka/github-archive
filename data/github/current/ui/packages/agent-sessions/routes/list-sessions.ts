import type {RepositoryNWO} from '@github-ui/current-repository'
import type {Session} from '../types/session'
import {mainQuery} from '@github-ui/react-core/future/query-configs'
import {agentSessionsAppBuilder} from '../config/app-builder'

export type ListSessionsResponse = {
  repository: RepositoryNWO
  sessions: Session[]
}

export const listSessionsRoute = agentSessionsAppBuilder.createQueryRouteConfig('listSessionsRoute', {
  path: '/:owner/:repo/sessions',
  index: true,
  queries: [mainQuery<ListSessionsResponse>()],
})

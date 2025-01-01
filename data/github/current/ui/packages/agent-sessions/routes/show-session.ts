import {agentSessionsAppBuilder} from '../config/app-builder'
import {mainQuery} from '@github-ui/react-core/future/query-configs'
import type {Session} from '../types/session'

export type SessionResponse = {
  session: Session
}

export const showSessionRoute = agentSessionsAppBuilder.createQueryRouteConfig('showSessionRoute', {
  path: '/:owner/:repo/sessions/:session_id',
  queries: [mainQuery<SessionResponse>()],
})

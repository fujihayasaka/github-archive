import type {Repository} from '@github-ui/current-repository'
import {agentSessionsAppBuilder} from '../config/app-builder'
import {mainQuery} from '@github-ui/react-core/future/main-query'
import type {LogEntry, Session} from '../types/session'
import type {PollingIntervals} from '../types/polling-intervals'
import type {Pull} from '../types/pull'

export type SessionResponse = {
  pull: Pull
  repository: Repository
  sessions: Session[]
  logs: LogEntry[]
  activeSessionId: string
  useMockData: boolean
  pollingIntervals: PollingIntervals
}

export const sessionRoute = agentSessionsAppBuilder.createQueryRouteConfig('sessionRoute', {
  path: '/:owner/:repo/pull/:id/agent-sessions/:session_id',
  queries: [mainQuery<SessionResponse>()],
})

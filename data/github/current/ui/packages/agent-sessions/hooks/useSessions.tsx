import {useQuery} from '@github-ui/react-query'
import {SessionState, type Session} from '../types/session'
import {AgentSessionsTokenProvider} from '@github-ui/copilot-auth-token/agent-sessions-token'
import mockSessions from '../mocks/sessions_response.json'
import {useCurrentRepository} from '@github-ui/current-repository'
import {usePullContext} from '../contexts/PullContext'

interface UseAgentSessionsProps {
  initialData: Session[]
  useMockData: boolean
  sessionsPollingInterval: number
}

export function useSessions({initialData, useMockData, sessionsPollingInterval}: UseAgentSessionsProps) {
  const repo = useCurrentRepository()
  const {
    pull: {id: pullId, number: pullNumber},
  } = usePullContext()
  const tokenProvider = useMockData ? null : new AgentSessionsTokenProvider(repo, pullNumber)

  return useQuery<Session[]>({
    queryKey: ['agent-sessions', repo.ownerLogin, repo.name, pullId, useMockData],
    queryFn: async () => {
      if (useMockData) {
        return mockSessions.sessions
      }

      const token = await tokenProvider?.getAuthToken()

      if (!token) {
        throw new Error('No token available')
      }

      const response = await fetch(`https://api.githubcopilot.com/agents/sessions/resource/pull/${pullId}`, {
        headers: {
          Authorization: token.authorizationHeaderValue,
          Accept: 'application/json',
        },
      })

      if (!response.ok) {
        throw new Error('Failed to fetch agent sessions')
      }

      const data = await response.json()
      return data.sessions
    },
    initialData,
    refetchInterval: query => {
      // Disable polling for mock data
      if (useMockData) return false

      const data = query.state.data
      // If no data yet, use default interval
      if (!data) return sessionsPollingInterval

      // Check if any sessions are in active/running state where we want to poll at the default rate
      const hasActiveSessions = data.some(
        session =>
          session.state === SessionState.InProgress ||
          session.state === SessionState.Idle ||
          session.state === SessionState.WaitingForUser,
      )

      // Slow down polling by a factor of 10 if there are no active sessions. Will speed back up
      // as soon as a session becomes active.
      return hasActiveSessions ? sessionsPollingInterval : sessionsPollingInterval * 10
    },
  })
}

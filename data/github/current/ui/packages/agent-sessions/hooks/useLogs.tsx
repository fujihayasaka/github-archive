import {useQuery} from '@github-ui/react-query'
import {SessionState, type LogEntry, type StreamingMessage} from '../types/session'
import {AgentSessionsTokenProvider} from '@github-ui/copilot-auth-token/agent-sessions-token'
import {makeCAPIRequest} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {CopilotChatMessageStreamer} from '@github-ui/copilot-chat/utils/copilot-chat-message-streamer'
import {useEffect, useRef, useState} from 'react'
import mockSessionLogs from '../mocks/session_logs_response.json'
import {useSessionContext} from '../contexts/SessionContext'
import {useCurrentRepository} from '@github-ui/current-repository'
import {usePullContext} from '../contexts/PullContext'

export const CONSECUTIVE_FAILURE_TOLERANCE = 10
const FIRST_FETCH_DELAY = 1000

export interface UseSessionLogsProps {
  useMockData: boolean
  logsPollingInterval: number
}

export function useLogs({useMockData, logsPollingInterval}: UseSessionLogsProps) {
  const {session} = useSessionContext()
  const repo = useCurrentRepository()
  const {
    pull: {number: pullNumber},
  } = usePullContext()
  const [consecutiveFailures, setConsecutiveFailures] = useState(0)
  const tokenProvider = useMockData ? null : new AgentSessionsTokenProvider(repo, pullNumber)
  const activeSessionId = session.id

  // Add a ref to track if this is the first fetch
  const isFirstFetch = useRef(true)

  const query = useQuery<LogEntry[]>({
    queryKey: [
      'agent-pr-session-logs',
      activeSessionId,
      repo.ownerLogin,
      repo.name,
      pullNumber,
      useMockData,
      consecutiveFailures,
      isFirstFetch.current,
    ],
    queryFn: async () => {
      // Add delay only for the first fetch
      if (isFirstFetch.current) {
        isFirstFetch.current = false
        await new Promise(resolve => setTimeout(resolve, FIRST_FETCH_DELAY))
      }

      if (useMockData) {
        setConsecutiveFailures(0)
        return mockSessionLogs.results as LogEntry[]
      }

      const token = await tokenProvider?.getAuthToken()

      if (!token) {
        throw new Error('No token available')
      }

      const result = await makeCAPIRequest({
        authToken: token,
        basePath: 'https://api.githubcopilot.com',
        method: 'GET',
        path: `/agents/sessions/${activeSessionId}/logs`,
        integrationId: 'copilot-developer-dev',
        streamingResponse: true,
      })

      if (!result.ok) {
        throw new Error('Failed to fetch session logs')
      }

      const reader = result.body?.getReader()
      if (!reader) {
        throw new Error('No reader found in response body')
      }

      const logs: LogEntry[] = []
      try {
        const streamer = new CopilotChatMessageStreamer<StreamingMessage>(reader)

        for await (const message of streamer.stream()) {
          logs.push({
            id: message.id,
            choices: message.choices,
          })
        }

        setConsecutiveFailures(0)
        return logs
      } catch (error) {
        throw new Error(`Error while streaming logs. Error: ${error}`)
      }
    },
    refetchInterval: session.state === SessionState.Completed ? false : logsPollingInterval,
    // Turn off log polling after 10 consecutive failures
    enabled: consecutiveFailures < CONSECUTIVE_FAILURE_TOLERANCE,
  })

  useEffect(() => {
    if (query.error) {
      setConsecutiveFailures(prev => prev + 1)
    }
  }, [query.error])

  const showPollingError = query.error && consecutiveFailures >= CONSECUTIVE_FAILURE_TOLERANCE

  return {
    ...query,
    showPollingError,
  }
}

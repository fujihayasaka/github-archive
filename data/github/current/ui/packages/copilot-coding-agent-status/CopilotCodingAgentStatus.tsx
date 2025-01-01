import {clsx} from 'clsx'
import {useSessions} from '@github-ui/agent-sessions/hooks/useSessions'
import {SessionState, type Session} from '@github-ui/agent-sessions/types/session'
import type {Pull} from '@github-ui/agent-sessions/types/pull'
import type {Repository} from '@github-ui/current-repository'
import {CurrentRepositoryProvider, useCurrentRepository} from '@github-ui/current-repository'
import {PullContextProvider, usePullContext} from '@github-ui/agent-sessions/contexts/PullContext'
import {Link} from '@primer/react'
import {ArrowBothIcon} from '@primer/octicons-react'
import styles from './CopilotCodingAgentStatus.module.css'
import {
  getSessionStatusIcon,
  getSessionStatusText,
  getSessionTimeDescription,
  generateSessionLink,
} from './CopilotCodingAgentSessionHelper'

function CopilotCodingAgentStatusWidget({
  initialActiveSession,
  useMockData,
  sessionsPollingInterval,
}: {
  initialActiveSession: Session
  useMockData: boolean
  sessionsPollingInterval: number
}) {
  const {
    data: sessionsData,
    isLoading: sessionsIsLoading,
    isError: sessionsIsError,
  } = useSessions({
    initialData: [initialActiveSession],
    useMockData,
    sessionsPollingInterval,
  })
  const {ownerLogin, name: repoName} = useCurrentRepository()
  const {
    pull: {number: pullNumber},
  } = usePullContext()

  const activeSession = sessionsData.at(-1)
  const sessionHref = generateSessionLink(ownerLogin, repoName, pullNumber, activeSession?.id ?? null)

  return (
    <Link
      href={sessionHref}
      className={clsx(
        styles.copilotCard,
        'fgColor-default rounded-2 no-underline mb-3 border d-flex flex-items-stretch',
      )}
    >
      <div className="mr-2 fgColor-muted d-flex flex-column flex-content-start flex-items-start">
        {getSessionStatusIcon(activeSession?.state ?? SessionState.Idle)}
      </div>

      <div className="flex-1">
        <p className="mb-0 fgColor-default text-semibold">
          {sessionsIsLoading && <div>Loading...</div>}
          {sessionsIsError && <div>Error</div>}
          {getSessionStatusText(activeSession?.state ?? SessionState.Idle)}
        </p>
        <p className="mb-0 fgColor-muted text-small">
          {activeSession &&
            getSessionTimeDescription(
              activeSession?.state,
              activeSession?.created_at,
              activeSession?.completed_at ?? '',
            )}
        </p>
      </div>

      <div className="ml-3 d-flex flex-column flex-justify-start">
        <div className="flex-self-start">
          <ArrowBothIcon className={`${styles.arrowBoth} fgColor-muted`} />
        </div>
      </div>
    </Link>
  )
}

export interface CopilotCodingAgentStatusProps {
  activeSession: Session
  repository: Repository
  pull: Pull
  useMockData: boolean
  sessionsPollingInterval: number
}

export function CopilotCodingAgentStatus({
  activeSession,
  repository,
  pull,
  useMockData,
  sessionsPollingInterval,
}: CopilotCodingAgentStatusProps) {
  return (
    <CurrentRepositoryProvider repository={repository}>
      <PullContextProvider pull={pull}>
        <CopilotCodingAgentStatusWidget
          initialActiveSession={activeSession}
          useMockData={useMockData}
          sessionsPollingInterval={sessionsPollingInterval}
        />
      </PullContextProvider>
    </CurrentRepositoryProvider>
  )
}

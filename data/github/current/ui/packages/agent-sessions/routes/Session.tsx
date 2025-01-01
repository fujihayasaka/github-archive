import {PageLayout} from '@primer/react'
import {SessionsHeader} from '../components/SessionsHeader'
import {SessionContent} from '../components/SessionContent'
import {SessionsNav} from '../components/SessionsNav'
import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {sessionRoute} from './session'
import {useState} from 'react'
import {updateUrl} from '@github-ui/history'
import {useSessions} from '../hooks/useSessions'
import {SessionContextProvider} from '../contexts/SessionContext'
import {CurrentRepositoryProvider, useCurrentRepository} from '@github-ui/current-repository'
import {PullContextProvider, usePullContext} from '../contexts/PullContext'
import type {Session} from '../types/session'

function SessionsLayout({
  initialSessions,
  initialActiveSessionId,
  useMockData,
  sessionsPollingInterval,
  logsPollingInterval,
}: {
  initialSessions: Session[]
  initialActiveSessionId: string
  useMockData: boolean
  sessionsPollingInterval: number
  logsPollingInterval: number
}) {
  const [activeSessionId, setActiveSessionId] = useState<string>(initialActiveSessionId)

  const {
    data: sessionsData,
    isLoading: sessionsIsLoading,
    isError: sessionsIsError,
  } = useSessions({
    initialData: initialSessions,
    useMockData,
    sessionsPollingInterval,
  })

  const {ownerLogin, name: repoName} = useCurrentRepository()
  const {
    pull: {number: pullNumber},
  } = usePullContext()

  const handleSessionChange = (id: string) => {
    setActiveSessionId(id)
    updateUrl(`/${ownerLogin}/${repoName}/pull/${pullNumber}/agent-sessions/${id}`)
    window.scrollTo({top: 0, behavior: 'auto'})
  }

  const activeSession = sessionsData.find(session => session.id === activeSessionId)

  return (
    <PageLayout containerWidth="full" padding="none" columnGap="normal" rowGap="none">
      <PageLayout.Header padding="none" className="px-4 pt-4 pb-0">
        <SessionsHeader />
      </PageLayout.Header>
      <PageLayout.Pane position="start" padding="none" sticky className="py-4 px-2 pl-md-2 pr-md-0 py-md-4">
        <SessionsNav
          sessionsData={sessionsData}
          sessionsIsLoading={sessionsIsLoading}
          sessionsIsError={sessionsIsError}
          onSessionChange={handleSessionChange}
          activeSessionId={activeSessionId}
        />
      </PageLayout.Pane>
      <PageLayout.Content as="div" padding="none" className="px-2 py-0 p-md-4 pl-md-0">
        {activeSession ? (
          <SessionContextProvider session={activeSession}>
            <SessionContent useMockData={useMockData} logsPollingInterval={logsPollingInterval} />
          </SessionContextProvider>
        ) : (
          // TODO: Improve loading state
          <div>Loading...</div>
        )}
      </PageLayout.Content>
    </PageLayout>
  )
}

export function Session() {
  const payload = useRouteQuery(sessionRoute, 'mainQuery')

  return (
    <CurrentRepositoryProvider repository={payload.data.repository}>
      <PullContextProvider pull={payload.data.pull}>
        <SessionsLayout
          initialSessions={payload.data.sessions}
          initialActiveSessionId={payload.data.activeSessionId}
          useMockData={payload.data.useMockData}
          sessionsPollingInterval={payload.data.pollingIntervals.sessionsPollingInterval}
          logsPollingInterval={payload.data.pollingIntervals.logsPollingInterval}
        />
      </PullContextProvider>
    </CurrentRepositoryProvider>
  )
}

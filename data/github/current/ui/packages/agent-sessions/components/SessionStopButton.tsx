import {Button} from '@primer/react'
import {SquareFillIcon} from '@primer/octicons-react'
import {SessionState} from '../types/session'
import {useSessionContext} from '../contexts/SessionContext'
import {usePullContext} from '../contexts/PullContext'
import {useCurrentRepository} from '@github-ui/current-repository'
import {useState} from 'react'
import {verifiedFetch} from '@github-ui/verified-fetch'

interface SessionStopStates {
  [key: string]: boolean
}

export function SessionStopButton() {
  const {session} = useSessionContext()
  const {
    pull: {number: pullNumber},
  } = usePullContext()
  const {ownerLogin, name: repoName, currentUserCanPush} = useCurrentRepository()

  const [sessionStopStates, setSessionStopStates] = useState<SessionStopStates>({})

  const stoppableStates: string[] = [SessionState.InProgress, SessionState.Idle, SessionState.WaitingForUser]
  const sessionStoppable = stoppableStates.includes(session.state)
  const stoppingSession = !!sessionStopStates[session.id]
  const buttonText = stoppingSession ? 'Stopping session...' : 'Stop session'

  const onSessionStop = async () => {
    if (stoppingSession) return

    // Ideally we wouldn't need to track this in this fashion and it would come from the session itself but we're not
    // quite there yet unfortunately
    setSessionStopStates({...sessionStopStates, [session.id]: true})

    await verifiedFetch(`/${ownerLogin}/${repoName}/pull/${pullNumber}/agent-sessions/${session.id}`, {
      method: 'DELETE',
    })
  }

  if (!currentUserCanPush) {
    // No button if the user cannot push to the repository because they lack authn to cancel the workflow
    return null
  }

  if (!sessionStoppable) {
    // No button if the session is not stoppable
    return null
  }

  return (
    <Button
      className="mr-2"
      leadingVisual={SquareFillIcon}
      variant="danger"
      onClick={onSessionStop}
      loading={stoppingSession}
      loadingAnnouncement="Stopping session"
      aria-disabled={stoppingSession}
    >
      {buttonText}
    </Button>
  )
}

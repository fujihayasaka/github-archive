import {NavList, Truncate} from '@primer/react'
import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {getSessionStatusIcon} from './StatusIcon'
import type {Session} from '../types/session'
import styles from './SessionsNav.module.css'
import SessionElapsedTime from './SessionElapsedTime'

interface SessionsNavProps {
  sessionsData: Session[] | undefined
  sessionsIsError: boolean
  sessionsIsLoading: boolean
  onSessionChange: (id: string) => void
  activeSessionId: string
}

export function SessionsNav({
  onSessionChange,
  sessionsData,
  sessionsIsError,
  sessionsIsLoading,
  activeSessionId,
}: SessionsNavProps) {
  return (
    <div aria-live="polite">
      <span className={`${styles.stepsTitle} text-small color-fg-muted`}>Sessions</span>

      {/* TODO: Improve error and empty states */}
      {sessionsIsError && <div>Error loading sessions. Retrying...</div>}
      {sessionsData && sessionsData.length === 0 && <div>No sessions to display</div>}
      {sessionsIsLoading ? (
        <NavList className={styles.stepsList}>
          <NavList.Item role="status">
            <LoadingSkeleton variant="rounded" className={styles.loadingSession} />
          </NavList.Item>
          <NavList.Item role="status">
            <LoadingSkeleton variant="rounded" className={styles.loadingSession} />
          </NavList.Item>
          <NavList.Item role="status">
            <LoadingSkeleton variant="rounded" className={styles.loadingSession} />
          </NavList.Item>
        </NavList>
      ) : (
        <NavList className={styles.stepsList}>
          {sessionsData &&
            sessionsData.map((session, i) => (
              <NavList.Item
                key={session.id}
                aria-labelledby={`session-name-${i + 1}`}
                onClick={() => onSessionChange(session.id)}
                aria-current={activeSessionId === session.id}
              >
                <NavList.LeadingVisual>{getSessionStatusIcon(session.state)}</NavList.LeadingVisual>
                <Truncate title={`Session ${i + 1}`}>{`Session ${i + 1}`}</Truncate>
                <NavList.TrailingVisual role="timer">
                  <SessionElapsedTime
                    createdAt={session.created_at}
                    completedAt={session.completed_at ?? ''}
                    state={session.state}
                  />
                </NavList.TrailingVisual>
              </NavList.Item>
            ))}
        </NavList>
      )}
    </div>
  )
}
export default SessionsNav

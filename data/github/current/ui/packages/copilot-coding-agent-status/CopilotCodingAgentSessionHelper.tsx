import {SessionState} from '@github-ui/agent-sessions/types/session'
import {CopilotIcon, CopilotWarningIcon, SquareFillIcon} from '@primer/octicons-react'
import {calculateElapsedTime} from '@github-ui/agent-sessions/utils/calculateElapsedTime'

export function getSessionStatusIcon(state: SessionState) {
  switch (state) {
    case SessionState.InProgress:
    case SessionState.WaitingForUser:
    case SessionState.Idle:
    case SessionState.Completed:
      return <CopilotIcon size="small" />
    case SessionState.Failed:
    case SessionState.TimedOut:
      return <CopilotWarningIcon size="small" className="fgColor-danger" />
    case SessionState.Cancelled:
      return <SquareFillIcon size="small" className="fgColor-muted" />
    default:
      return <CopilotIcon size="small" />
  }
}

export function getSessionStatusText(state: SessionState) {
  switch (state) {
    case SessionState.InProgress:
      return 'In progress'
    case SessionState.WaitingForUser:
      return 'Copilot is waiting for your input'
    case SessionState.Idle:
      return 'Copilot is blocked'
    case SessionState.Completed:
      return 'Copilot is done'
    case SessionState.Failed:
      return 'Copilot has failed'
    case SessionState.TimedOut:
      return 'Copilot has timed out'
    case SessionState.Cancelled:
      return 'Copilot was manually stopped'
    default:
      return 'In progress'
  }
}

export function getSessionTimeDescription(state: SessionState, createdAt: string | Date, completedAt?: string | Date) {
  const created = new Date(createdAt).toISOString()
  const elapsedTime = calculateElapsedTime(createdAt, completedAt)
  switch (state) {
    case SessionState.Completed:
      return (
        <span role="timer">
          completed after <time aria-live="off">{elapsedTime}</time>
        </span>
      )
    case SessionState.Failed:
      return (
        <span role="timer">
          failed after <time aria-live="off">{elapsedTime}</time>
        </span>
      )
    case SessionState.TimedOut:
      return (
        <span role="timer">
          timed out after <time aria-live="off">{elapsedTime}</time>
        </span>
      )
    case SessionState.Cancelled:
      return (
        <span role="timer">
          session stopped after <time aria-live="off">{elapsedTime}</time>
        </span>
      )
    default:
      return (
        <span role="timer">
          started <relative-time datetime={created} tense="past" />
        </span>
      )
  }
}

export function generateSessionLink(
  ownerLogin: string,
  repoName: string,
  pullNumber: number,
  sessionId: string | null,
): string | undefined {
  if (ownerLogin == null || repoName == null || pullNumber == null) {
    return undefined
  }

  return `/${ownerLogin}/${repoName}/pull/${pullNumber}/agent-sessions/${sessionId ? sessionId : ''}`
}

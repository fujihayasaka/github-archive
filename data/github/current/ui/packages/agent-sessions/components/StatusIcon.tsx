import {CheckCircleFillIcon, XCircleFillIcon, QuestionIcon, DotFillIcon, SquareFillIcon} from '@primer/octicons-react'
import {SessionState} from '../types/session'

export function getSessionStatusIcon(status: SessionState) {
  switch (status) {
    case SessionState.InProgress:
      return <InProgressSpinner />
    case SessionState.Completed:
      return <CheckCircleFillIcon className="fgColor-success" aria-label="Completed" />
    case SessionState.Failed:
    case SessionState.TimedOut:
      return <XCircleFillIcon className="fgColor-danger" aria-label="Failed" />
    case SessionState.Idle:
      return <DotFillIcon className="fgColor-attention" aria-label="Idle" />
    case SessionState.WaitingForUser:
      return <QuestionIcon className="fgColor-attention" aria-label="Waiting for user" />
    case SessionState.Cancelled:
      return <SquareFillIcon className="fgColor-muted" aria-label="Cancelled" />
    default:
      return null
  }
}

function InProgressSpinner() {
  return (
    <svg
      aria-label="Currently running"
      width="16px"
      height="16px"
      fill="none"
      viewBox="0 0 16 16"
      className="anim-rotate"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        fill="none"
        stroke="var(--color-fg-attention, #bf8700)"
        strokeWidth="2"
        d="M3.05 3.05a7 7 0 1 1 9.9 9.9 7 7 0 0 1-9.9-9.9Z"
        opacity=".5"
      />
      <path
        fill="var(--color-fg-attention, #bf8700)"
        fillRule="evenodd"
        d="M8 4a4 4 0 1 0 0 8 4 4 0 0 0 0-8Z"
        clipRule="evenodd"
      />
      <path fill="var(--color-fg-attention, #bf8700)" d="M14 8a6 6 0 0 0-6-6V0a8 8 0 0 1 8 8h-2Z" />
    </svg>
  )
}

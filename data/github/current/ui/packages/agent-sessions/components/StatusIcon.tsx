import {CheckCircleFillIcon, XCircleFillIcon, QuestionIcon} from '@primer/octicons-react'

export type StepStatus = 'success' | 'error' | 'blocked' | 'in-progress'

export function getStepStatusIcon(status: StepStatus) {
  switch (status) {
    case 'in-progress':
      return <InProgressSpinner />
    case 'success':
      return <CheckCircleFillIcon className="fgColor-success" />
    case 'error':
      return <XCircleFillIcon className="fgColor-danger" />
    case 'blocked':
      {
        /* TODO: Exclamation icon doesn't exist in Octicons - ask design about it */
      }
      return <QuestionIcon className="fgColor-danger" />
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
        stroke="#DBAB0A"
        strokeWidth="2"
        d="M3.05 3.05a7 7 0 1 1 9.9 9.9 7 7 0 0 1-9.9-9.9Z"
        opacity=".5"
      />
      <path fill="#DBAB0A" fillRule="evenodd" d="M8 4a4 4 0 1 0 0 8 4 4 0 0 0 0-8Z" clipRule="evenodd" />
      <path fill="#DBAB0A" d="M14 8a6 6 0 0 0-6-6V0a8 8 0 0 1 8 8h-2Z" />
    </svg>
  )
}

export type StatusCheckState =
  | 'ACTION_REQUIRED'
  | 'CANCELLED'
  | 'COMPLETED'
  | 'ERROR'
  | 'EXPECTED'
  | 'FAILURE'
  | 'IN_PROGRESS'
  | 'NEUTRAL'
  | 'PENDING'
  | 'QUEUED'
  | 'REQUESTED'
  | 'SKIPPED'
  | 'STALE'
  | 'STARTUP_FAILURE'
  | 'SUCCESS'
  | 'TIMED_OUT'
  | 'WAITING'
  | '_UNKNOWN_VALUE'

export type CombinedState =
  | 'FAILED'
  | 'PASSED'
  | 'PENDING'
  | 'PENDING_APPROVAL'
  | 'PENDING_FAILED'
  | 'SOME_FAILED'
  | 'PENDING_CONFLICTS'

export type CheckStateRollup = {
  state: StatusCheckState
  count: number
}

export type AliveChannels = {
  commitHeadShaChannel: string
}

export type PendingWorkflowApprovalRollup = {
  workflowsRequiringApprovalCount: number
  viewerCanApproveWorkflowRuns: boolean
  hasExpiredWorkflowRuns: boolean
  approvalRequiredMessage: string
  helpLink: string
}

export type StatusRollup = {
  summary: CheckStateRollup[]
  combinedState: CombinedState
  pendingWorkflowApprovalRollup: PendingWorkflowApprovalRollup | null
}

export type CopilotCheckRunFailureContext = {
  jobId: number
}

export type StatusCheck = {
  additionalContext: string
  avatarUrl: string
  copilotCheckRunFailureContext?: CopilotCheckRunFailureContext | null
  description: string
  displayName: string
  durationInSeconds: number
  isRequired: boolean
  state: StatusCheckState
  stateChangedAt: string
  targetUrl: string | null
}

export type StatusChecksPageData = {
  aliveChannels: AliveChannels
  statusRollup: StatusRollup
  statusChecks: StatusCheck[]
}

function exhaustiveCheck(_param: never) {}
// We added the exhaustiveCheck here so that we would be safeguarded if new StatusCheckStates are added
export function isFailingOrIncompleteStatus(state: StatusCheckState) {
  switch (state) {
    case 'ACTION_REQUIRED':
    case 'FAILURE':
    case 'ERROR':
    case 'STARTUP_FAILURE':
    case '_UNKNOWN_VALUE':
      return true
    // incomplete states
    case 'CANCELLED':
    case 'STALE':
    case 'TIMED_OUT':
      return true
    case 'SUCCESS':
    case 'COMPLETED':
    case 'EXPECTED':
    case 'IN_PROGRESS':
    case 'NEUTRAL':
    case 'PENDING':
    case 'QUEUED':
    case 'REQUESTED':
    case 'SKIPPED':
    case 'WAITING':
      return false
    default:
      exhaustiveCheck(state)
  }
}
export function isPendingStatus(state: StatusCheckState) {
  switch (state) {
    case 'WAITING':
    case 'PENDING':
    case 'IN_PROGRESS':
    case 'QUEUED':
    case 'EXPECTED':
      return true
    case 'ACTION_REQUIRED':
    case 'FAILURE':
    case 'ERROR':
    case 'STARTUP_FAILURE':
    case 'CANCELLED':
    case 'STALE':
    case 'TIMED_OUT':
    case 'SUCCESS':
    case 'COMPLETED':
    case 'NEUTRAL':
    case 'REQUESTED':
    case 'SKIPPED':
    case '_UNKNOWN_VALUE':
      return false
    default:
      exhaustiveCheck(state)
  }
}

export function isSuccessStatus(state: StatusCheckState) {
  switch (state) {
    case 'NEUTRAL':
    case 'SUCCESS':
    case 'SKIPPED':
      return true
    case 'WAITING':
    case 'PENDING':
    case 'IN_PROGRESS':
    case 'QUEUED':
    case 'EXPECTED':
    case 'ACTION_REQUIRED':
    case 'FAILURE':
    case 'ERROR':
    case 'STARTUP_FAILURE':
    case 'CANCELLED':
    case 'STALE':
    case 'TIMED_OUT':
    case 'COMPLETED':
    case 'REQUESTED':
    case '_UNKNOWN_VALUE':
      return false
    default:
      exhaustiveCheck(state)
  }
}

import type {FilterableRequestStatus} from '../delegated-bypass-types'

export const orderedStatuses: FilterableRequestStatus[] = [
  'all',
  'completed',
  'cancelled',
  'expired',
  'approved',
  'denied',
  'open',
]
export const requestStatuses: Record<FilterableRequestStatus, string> = {
  all: 'All statuses',
  completed: 'Completed',
  cancelled: 'Cancelled',
  expired: 'Expired',
  approved: 'Approved',
  denied: 'Denied',
  open: 'Open',
}

export const UpdateState = {
  Initial: 'initial',
  Submitting: 'submitting',
  Success: 'success',
  Error: 'error',
  Redirecting: 'redirecting',
} as const

export type UpdateState = (typeof UpdateState)[keyof typeof UpdateState]

export const IssueStateReason = {
  COMPLETED: 'COMPLETED',
  NOT_PLANNED: 'NOT_PLANNED',
  DUPLICATE: 'DUPLICATE',
  REOPENED: 'REOPENED',
}
export type IssueStateReasonType = keyof typeof IssueStateReason | null | undefined

export const IssueState = {
  OPEN: 'OPEN',
  CLOSED: 'CLOSED',
}
export type IssueStateType = keyof typeof IssueState
export type PullRequestStateType = IssueStateType | 'MERGED' | 'IN_MERGE_QUEUE' | 'DRAFT' | undefined | null

export const IssueStateReasonStrings = {
  COMPLETED: 'completed',
  NOT_PLANNED: 'not planned',
  DUPLICATE: 'duplicate',
  REOPENED: 'reopened',
}

export const IssueStateChangeQuery = {
  COMPLETED: 'is:issue state:closed archived:false reason:completed',
  NOT_PLANNED: 'is:issue state:closed archived:false reason:not-planned',
  DUPLICATE: 'is:issue state:closed archived:false reason:duplicate',
  REOPENED: '',
}

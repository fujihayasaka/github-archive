/**
 * These represent the merge box page data payloads from the JSON API.
 */
import type {
  AutoMergeRequest,
  MergeQueue,
  MergeStateStatus,
  PullRequestState,
  ViewerMergeActions,
  PendingReviewRequest,
  PullRequestMergeRequirementsState,
  PullRequestMergeConditionResult,
  OpinionatedReview,
  MergeConditionType,
  RuleRollupPayload,
  MergeQueueEntry,
} from '../../types'

export type JSONAPIPullRequestPayload = {
  autoMergeRequest: AutoMergeRequest | null
  baseRefName: string
  headRefName: string
  headRefOid: string
  headRepository: {
    name: string
    ownerLogin: string
  } | null
  id: string
  isCrossRepo: boolean
  isDraft: boolean
  isInMergeQueue: boolean
  latestOpinionatedReviews: OpinionatedReview[]
  mergeBoxAliveChannels: {
    baseRefChannel: string
    commitHeadShaChannel: string
    deployedChannel: string
    gitMergeStateChannel: string
    headRefChannel: string | null
    mergeQueueChannel: string
    reviewStateChannel: string
    stateChannel: string
    workflowsChannel: string
    pullRequestChannel: string
  }
  mergeQueue: MergeQueue | null
  mergeQueueEntry: MergeQueueEntry
  mergeStateStatus: MergeStateStatus
  numberOfCommits: number
  pendingReviewRequests: PendingReviewRequest[]
  resourcePath: string
  state: PullRequestState
  viewerCanAddAndRemoveFromMergeQueue: boolean
  viewerCanAdminBypassMergeRequirements: boolean
  viewerCanAddToMergeQueueSolo: boolean
  viewerCanDeleteHeadRef: boolean
  viewerCanDisableAutoMerge: boolean
  viewerCanEnableAutoMerge: boolean
  viewerCanRestoreHeadRef: boolean
  viewerCanUpdate: boolean
  viewerCanUpdateBranch: boolean
  viewerDidAuthor: boolean
  viewerMergeActions: ViewerMergeActions
  viewerCanDismissReviews: boolean
  viewerCanReRequestReviews: boolean
}

export type MergeConditionPayload = {
  type: MergeConditionType
  displayName: string
  description: string
  message: string | null | undefined
  result: PullRequestMergeConditionResult
  ruleRollups: RuleRollupPayload[] | null | undefined
}

type MergeRequirementsConditionsPayload = Array<MergeConditionPayload | ConflictMergeConditionPayload>
export type ConflictMergeConditionPayload = {
  type: 'PULL_REQUEST_MERGE_CONFLICT_STATE'
  displayName: string
  description: string
  message: string | null
  result: PullRequestMergeConditionResult
  ruleRollups: RuleRollupPayload[] | null
  conflicts: string[] | null | undefined
  isConflictResolvableInWeb: boolean | null | undefined
}

export type PullRequestMergeRequirementsPayload = {
  conditions: MergeRequirementsConditionsPayload
  state: PullRequestMergeRequirementsState
  commitAuthorEmail: string
  commitMessageBody: string | null | undefined
  commitMessageHeadline: string | null | undefined
}

export type MergeBoxPageData = {
  mergeRequirements: PullRequestMergeRequirementsPayload | null
  pullRequest: JSONAPIPullRequestPayload
}

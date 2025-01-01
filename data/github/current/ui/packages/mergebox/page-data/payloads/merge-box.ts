/**
 * These represent the merge box page data payloads from the JSON API.
 */
import type {
  AdvisoryWorkspace,
  AutoMergeRequest,
  DeprovisionableCodespaces,
  FailingSubConditionPayload,
  MergeConditionType,
  MergeQueue,
  MergeQueueEntry,
  MergeStateStatus,
  OpinionatedReview,
  PendingReviewRequest,
  PullRequestMergeConditionResult,
  PullRequestMergeRequirementsState,
  PullRequestState,
  RuleRollupPayload,
  ViewerMergeActions,
  ViewerUpdateMethods,
} from '../../types'

export type Repository = {
  ownerLogin: string
  name: string
  url: string
} | null

export type MergeBoxUserPreferences = {
  statusChecksGrouping: 'grouped_by_status' | 'ungrouped'
}

export type JSONAPIPullRequestPayload = {
  advisoryWorkspace: AdvisoryWorkspace | null
  autoMergeRequest: AutoMergeRequest | null
  baseRefName: string
  deprovisionableCodespaces: DeprovisionableCodespaces | null
  headRefName: string
  headRefOid: string
  headRepository: Repository
  baseRepository: Repository
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
  mergeBoxUserPreferences: MergeBoxUserPreferences | null
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
  viewerUpdateMethods: ViewerUpdateMethods | null
}

// Merge Conditions are union types of different types of conditions that can be present
// in the merge requirements payload. Each condition type has a different set of properties
// that are relevant to that condition type. The `type` property is used to determine which properties are present in the payload.
// This gives us more nuanced type control on the client side.
export type MergeConditionPayload =
  | RepositoryRulesMergeConditionPayload
  | MergeConditionWithSubConditionsPayload
  | GenericMergeConditionPayload
  | ConflictMergeConditionPayload

// All merge conditions have these properties
type BaseMergeConditionPayload = {
  type: MergeConditionType
  displayName: string
  description: string
  message: string | null | undefined
  result: PullRequestMergeConditionResult
}

// The rule rollup condition type - these come from the rules engine
export type RepositoryRulesMergeConditionPayload = BaseMergeConditionPayload & {
  type: 'PULL_REQUEST_RULES'
  ruleRollups: RuleRollupPayload[]
}

// The condition type with sub conditions - these are manual checks not sourced from the rules engine
// This are used when we want more fine-grained control over the message and display of the condition
export type MergeConditionWithSubConditionsPayload = BaseMergeConditionPayload & {
  type: 'PULL_REQUEST_USER_STATE'
  failedSubConditions: FailingSubConditionPayload[]
}

export type MergeConflictWebEditorResolution = {
  viewerCanResolve: boolean
  viewerCannotResolve: {
    reason: 'INSUFFICIENT_ACCESS' | 'TOO_COMPLEX' | 'HEAD_BRANCH_PROTECTED' | 'ADMIN_DISABLED'
    message: string
  } | null
}

// The merge conflict condition type - these are special conditions that are only present when there are merge conflicts
export type ConflictMergeConditionPayload = BaseMergeConditionPayload & {
  type: 'PULL_REQUEST_MERGE_CONFLICT_STATE'
  conflicts: string[] | null | undefined
  webEditorConflictResolution: MergeConflictWebEditorResolution | null | undefined
  // TODO: Deprecate in follow up PR
  isConflictResolvableInWeb: boolean
}

// Everything else is a merge condition without a rule rollup - these are simple conditions
export type GenericMergeConditionPayload = BaseMergeConditionPayload & {
  type: Exclude<
    MergeConditionType,
    'PULL_REQUEST_RULES' | 'PULL_REQUEST_USER_STATE' | 'PULL_REQUEST_MERGE_CONFLICT_STATE'
  >
}

export type PullRequestMergeRequirementsPayload = {
  conditions: MergeConditionPayload[]
  state: PullRequestMergeRequirementsState
  defaultCommitAuthorEmail: string | null | undefined
  commitMessageBody: string | null | undefined
  commitMessageHeadline: string | null | undefined
  possibleCommitAuthorEmails: string[]
}

export type MergeBoxPageData = {
  mergeRequirements: PullRequestMergeRequirementsPayload | null
  pullRequest: JSONAPIPullRequestPayload
}

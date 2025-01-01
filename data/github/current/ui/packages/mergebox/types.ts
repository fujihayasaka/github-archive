/**
 * TYPES
 */

export const MergeAction = {
  DIRECT_MERGE: 'DIRECT_MERGE',
  AUTO_MERGE: 'AUTO_MERGE',
  MERGE_QUEUE: 'MERGE_QUEUE',
} as const

export type MergeAction = (typeof MergeAction)[keyof typeof MergeAction]

export const MergeMethod = {
  MERGE: 'MERGE',
  SQUASH: 'SQUASH',
  REBASE: 'REBASE',
} as const

export type MergeMethod = (typeof MergeMethod)[keyof typeof MergeMethod]

export const MergeQueueMethod = {
  GROUP: 'GROUP',
  SOLO: 'SOLO',
} as const

export type MergeQueueMethod = (typeof MergeQueueMethod)[keyof typeof MergeQueueMethod]

export type CheckRunState =
  | 'ACTION_REQUIRED'
  | 'CANCELLED'
  | 'COMPLETED'
  | 'FAILURE'
  | 'IN_PROGRESS'
  | 'NEUTRAL'
  | 'PENDING'
  | 'QUEUED'
  | 'SKIPPED'
  | 'STALE'
  | 'STARTUP_FAILURE'
  | 'SUCCESS'
  | 'TIMED_OUT'
  | 'WAITING'

export type StatusState = 'ERROR' | 'EXPECTED' | 'FAILURE' | 'PENDING' | 'SUCCESS'

export type CheckConclusionState =
  | 'ACTION_REQUIRED'
  | 'CANCELLED'
  | 'FAILURE'
  | 'NEUTRAL'
  | 'SKIPPED'
  | 'STALE'
  | 'STARTUP_FAILURE'
  | 'SUCCESS'
  | 'TIMED_OUT'

export type CheckStatusState = 'COMPLETED' | 'IN_PROGRESS' | 'PENDING' | 'QUEUED' | 'REQUESTED' | 'WAITING'

export type PullRequestMergeConditionResult = 'FAILED' | 'PASSED' | 'UNKNOWN'

export type PullRequestMergeRequirementsState = 'MERGEABLE' | 'UNKNOWN' | 'UNMERGEABLE' | 'MERGEABLE_IF_STATUSES_PASS'

export type PullRequestMergeMethodStatus = 'ALLOWED' | 'BLOCKED' | 'ALLOWED_WITH_BYPASS' | 'UNAVAILABLE'

export type PullRequestUpdateMethod = 'MERGE' | 'REBASE'

export type PullRequestMergeMethod = 'MERGE' | 'REBASE' | 'SQUASH'

export type PullRequestMergeAction = 'DIRECT_MERGE' | 'MERGE_QUEUE'

export type PullRequestState = 'CLOSED' | 'MERGED' | 'OPEN'

export type MergeStateStatus = 'BEHIND' | 'BLOCKED' | 'CLEAN' | 'DIRTY' | 'DRAFT' | 'HAS_HOOKS' | 'UNKNOWN' | 'UNSTABLE'

export type PullRequestRuleFailureReason =
  | 'CHANGES_REQUESTED'
  | 'CODE_OWNER_REVIEW_REQUIRED'
  | 'MORE_REVIEWS_REQUIRED'
  | 'SOC2_APPROVAL_PROCESS_REQUIRED'
  | 'THREAD_RESOLUTION_REQUIRED'
  | 'LAST_PUSH_APPROVAL_REQUIRED'

export type RepositoryRuleType =
  | 'AUTHORIZATION'
  | 'BRANCH_NAME_PATTERN'
  | 'CODE_SCANNING'
  | 'COMMITTER_EMAIL_PATTERN'
  | 'COMMIT_AUTHOR_EMAIL_PATTERN'
  | 'COMMIT_MESSAGE_PATTERN'
  | 'COMMIT_OID'
  | 'CREATION'
  | 'DELETION'
  | 'FILE_EXTENSION_RESTRICTION'
  | 'FILE_PATH_RESTRICTION'
  | 'LOCK_BRANCH'
  | 'MAX_FILE_PATH_LENGTH'
  | 'MAX_FILE_SIZE'
  | 'MAX_REF_UPDATES'
  | 'MERGE_QUEUE'
  | 'MERGE_QUEUE_LOCKED_REF'
  | 'NON_FAST_FORWARD'
  | 'PULL_REQUEST'
  | 'REQUIRED_DEPLOYMENTS'
  | 'REQUIRED_LINEAR_HISTORY'
  | 'REQUIRED_REVIEW_THREAD_RESOLUTION'
  | 'REQUIRED_SIGNATURES'
  | 'REQUIRED_STATUS_CHECKS'
  | 'REQUIRED_WORKFLOW_STATUS_CHECKS'
  | 'REPOSITORY_DELETE'
  | 'REPOSITORY_TRANSFER'
  | 'SECRET_SCANNING'
  | 'TAG'
  | 'TAG_NAME_PATTERN'
  | 'UPDATE'
  | 'WORKFLOWS'
  | 'WORKFLOW_UPDATES'
  | 'REPOSITORY_DELETE'
  | 'REPOSITORY_NAME'
  | 'REPOSITORY_VISIBILITY'
  | 'REPOSITORY_CREATE'

export type PullRequestReviewState = 'APPROVED' | 'CHANGES_REQUESTED' | 'COMMENTED' | 'DISMISSED' | 'PENDING'

export type ViewerUpdateMethods = ReadonlyArray<{
  allowableStatus: PullRequestMergeMethodStatus
  isDefault: boolean
  name: PullRequestUpdateMethod
  failureReason: string | null
}>
export type ViewerMergeMethods = ReadonlyArray<{
  isAllowable: boolean
  isAllowableWithBypass: boolean
  name: PullRequestMergeMethod
}>

export type ViewerMergeActions = ReadonlyArray<{
  isAllowable: boolean
  mergeMethods: ViewerMergeMethods
  name: PullRequestMergeAction
}>

export type AdvisoryWorkspace =
  | {
      advisoryWorkspaceId: string | null
      advisoryWorkspacePath: string | null
    }
  | null
  | undefined

export type AutoMergeRequest =
  | {
      mergeMethod: PullRequestMergeMethod
    }
  | null
  | undefined

export type DeprovisionableCodespaces =
  | {
      count: number
      repositoryCodespacePath: string
    }
  | null
  | undefined

export type MergeQueue =
  | {
      url: string
    }
  | null
  | undefined

export type MergeQueueEntry = {
  position: number
  state: MergeQueueEntryState
  isLocked: boolean
} | null

export type MergeQueueEntryState = 'AWAITING_CHECKS' | 'WAITING' | 'MERGEABLE' | 'QUEUED' | 'UNMERGEABLE'

export type Author = {
  login: string
  avatarUrl: string
  name: string
  url: string
}

export const ReviewGroup = {
  Approvals: 'approvals',
  RequestedChanges: 'requested changes',
  PendingReviewRequest: 'pending reviews',
} as const

export type ReviewGroup = (typeof ReviewGroup)[keyof typeof ReviewGroup]

type ReviewerType = 'TEAM' | 'USER'

export type Reviewer = {
  login: string
  avatarUrl: string
  name: string
  url: string
  type: ReviewerType
}

export type OpinionatedReview = {
  id: number
  authorCanPushToRepository: boolean
  author: Author | null
  onBehalfOf: string[]
  state: PullRequestReviewState
}

export type PendingReviewRequest = {
  reviewer: Reviewer | null
  isCodeOwner: boolean
}

export type ReviewerRuleRollup = {
  requiredReviewers?: number
  requiresCodeowners?: boolean
  failureReasons?: PullRequestRuleFailureReason[]
}

export type ReviewerRuleMetadata = {
  requiredReviewers: number
  requiresCodeowners: boolean
  failureReasons: string[] // this is snake case, all lower case
}

// Failed Sub Condition
export type FailingSubConditionPayload = {
  displayName: string
  message: string | null | undefined
}

// Failed Rollup of Conditions, Rules, and Sub Condtions
export type FailingRulesAndConditionPayload = {
  displayName: string
  message: string | null | undefined
}

type RuleRollupResult = 'PASSED' | 'FAILED'

// Rules Engine Rollup
export type RuleRollupPayload = {
  ruleType: RepositoryRuleType
  displayName: string
  message: string | null | undefined
  result: RuleRollupResult
  bypassable: boolean
  metadata: RuleSpecificMetadata | null
}

type RuleSpecificMetadata =
  | ReviewerRuleMetadata
  | {
      statusCheckResults: Array<{context: string; integrationId: number | null; result: string}>
    }
  | {
      missingEnvironments: string[]
      DeployedEnvironments: string[]
    }

export type MergeConditionType =
  | 'PULL_REQUEST_STATE'
  | 'PULL_REQUEST_REPO_STATE'
  | 'PULL_REQUEST_USER_STATE'
  | 'PULL_REQUEST_RULES'
  | 'PULL_REQUEST_MERGE_CONFLICT_STATE'
  | 'PULL_REQUEST_MERGE_METHOD'
  | 'UNKNOWN'

export const MergeConditionsWithRepositoryRules: MergeConditionType[] = ['PULL_REQUEST_RULES']
export const MergeConditionsWithSubConditions: MergeConditionType[] = ['PULL_REQUEST_USER_STATE']
export const MergeConditionsConflict: MergeConditionType[] = ['PULL_REQUEST_MERGE_CONFLICT_STATE']
export const MergeConditionsGeneral: MergeConditionType[] = [
  'PULL_REQUEST_STATE',
  'PULL_REQUEST_MERGE_METHOD',
  'PULL_REQUEST_REPO_STATE',
  'UNKNOWN',
]

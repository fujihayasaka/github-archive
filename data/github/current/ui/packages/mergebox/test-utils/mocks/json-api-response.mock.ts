import type {
  ConflictMergeConditionPayload,
  JSONAPIPullRequestPayload,
  MergeBoxPageData,
  MergeConditionPayload,
  MergeConflictWebEditorResolution,
  PullRequestMergeRequirementsPayload,
} from '../../page-data/payloads/merge-box'
import {
  MergeAction,
  MergeMethod,
  type FailingSubConditionPayload,
  type MergeConditionType,
  type PullRequestMergeConditionResult,
  type RuleRollupPayload,
  type ViewerMergeActions,
} from '../../types'
import {
  baseRefChannel,
  commitHeadShaChannel,
  deployedChannel,
  gitMergeStateChannel,
  headRefChannel,
  mergeQueueChannel,
  pullRequestChannel,
  reviewStateChannel,
  stateChannel,
  workflowsChannel,
} from './alive-channels-mock'

type MergeBoxDataOptions = {
  pullRequestKind?: PullRequestKind
  mergeRequirementsKind?: MergeRequirementsKind
}

/**
 * Returns a mock response from the JSON API for the merge box page data.
 *
 * Pass the kind of preset state for a pull request or the merge requirements you need to test.
 * Typically, we want to use preset states rather than configuring the data ourselves, which is prone to error. However, if this function does not meet your needs, you are welcome to either add additional states or use the escape hatches (via exported objects below).
 */
export function mergeBoxMockData({
  pullRequestKind = 'default',
  mergeRequirementsKind = 'default',
}: MergeBoxDataOptions = {}): MergeBoxPageData {
  return {
    pullRequest: mockPullRequest[pullRequestKind],
    mergeRequirements: mockMergeRequirements[mergeRequirementsKind],
  }
}

/**
 * A default pull request - an escape hatch if mergeBoxMockData is too opinionated.
 */
export const defaultPullRequest: JSONAPIPullRequestPayload = {
  advisoryWorkspace: null,
  autoMergeRequest: null,
  baseRefName: 'master',
  deprovisionableCodespaces: null,
  headRefOid: '123456789',
  headRefName: 'prx/test-branch',
  headRepository: {
    ownerLogin: 'monalisa',
    name: 'smile',
    url: '/monalisa/smile',
  },
  baseRepository: {
    ownerLogin: 'github',
    name: 'smile',
    url: '/github/smile',
  },
  id: 'PR_123',
  isCrossRepo: false,
  isDraft: false,
  isInMergeQueue: false,
  latestOpinionatedReviews: [
    {
      id: 12345,
      authorCanPushToRepository: true,
      author: {
        login: 'collaborator',
        avatarUrl: 'https://avatars.githubusercontent.com/u/12345?v=4',
        name: 'collaborator',
        url: 'https://github.com/collaborator',
      },
      onBehalfOf: ['my-cool-team'],
      state: 'APPROVED',
    },
    {
      id: 12346,
      authorCanPushToRepository: true,
      author: {
        login: 'octocat',
        avatarUrl: 'https://avatars.githubusercontent.com/u/678910?v=4',
        name: 'octocat',
        url: 'https://github.com/octocat',
      },
      onBehalfOf: ['my-cool-team-reviewers'],
      state: 'CHANGES_REQUESTED',
    },
  ],
  mergeBoxAliveChannels: {
    stateChannel,
    deployedChannel,
    reviewStateChannel,
    workflowsChannel,
    mergeQueueChannel,
    headRefChannel,
    baseRefChannel,
    commitHeadShaChannel,
    gitMergeStateChannel,
    pullRequestChannel,
  },
  mergeBoxUserPreferences: {
    statusChecksGrouping: 'grouped_by_status',
  },
  mergeQueue: {
    url: 'https://github.com/monalisa/smile/queue/master',
  },
  mergeQueueEntry: null,
  mergeStateStatus: 'BLOCKED',
  numberOfCommits: 15,
  pendingReviewRequests: [
    {
      reviewer: {
        login: 'betty',
        avatarUrl: 'https://avatars.githubusercontent.com/u/12345?v=4',
        name: 'Betty',
        url: 'https://github.com/betty',
        type: 'USER',
      },
      isCodeOwner: false,
    },
    {
      reviewer: {
        login: 'juan-mayor',
        avatarUrl: 'https://avatars.githubusercontent.com/u/12345?v=4',
        name: 'Juan Mayor',
        url: 'https://github.com/juan-mayor',
        type: 'USER',
      },
      isCodeOwner: true,
    },
  ],
  resourcePath: 'https://github.com/github/github/pull/337434',
  state: 'OPEN',
  viewerCanAddAndRemoveFromMergeQueue: true,
  viewerCanDeleteHeadRef: false,
  viewerCanReRequestReviews: true,
  viewerCanDismissReviews: true,
  viewerCanDisableAutoMerge: false,
  viewerCanEnableAutoMerge: true,
  viewerCanAddToMergeQueueSolo: false,
  viewerCanRestoreHeadRef: false,
  viewerCanUpdateBranch: true,
  viewerCanUpdate: true,
  viewerDidAuthor: true,
  viewerCanAdminBypassMergeRequirements: false,
  viewerUpdateMethods: [
    {
      allowableStatus: 'ALLOWED',
      name: 'MERGE',
      failureReason: null,
      isDefault: true,
    },
    {
      allowableStatus: 'ALLOWED',
      name: 'REBASE',
      failureReason: null,
      isDefault: false,
    },
  ],
  viewerMergeActions: [
    {
      allowableStatus: 'ALLOWED',
      mergeMethods: [
        {
          allowableStatus: 'BLOCKED',
          name: 'MERGE',
          // This is returned, but not currently needed
          // isDefault: true,
        },
        {
          allowableStatus: 'BLOCKED',
          name: 'SQUASH',
          // This is returned, but not currently needed
          // isDefault: false,
        },
        {
          allowableStatus: 'BLOCKED',
          name: 'REBASE',
          // This is returned, but not currently needed
          // isDefault: false,
        },
      ],
      name: 'MERGE_QUEUE',
      // This is returned, but not currently needed
      // allowableStatus: 'BLOCKED',
    },
    {
      allowableStatus: 'BLOCKED',
      mergeMethods: [
        {
          allowableStatus: 'BLOCKED',
          name: 'MERGE',
          // This is returned, but not currently needed
          // isDefault: true,
        },
        {
          allowableStatus: 'BLOCKED',
          name: 'SQUASH',
          // This is returned, but not currently needed
          // isDefault: false,
        },
        {
          allowableStatus: 'BLOCKED',
          name: 'REBASE',
          // This is returned, but not currently needed
          // isDefault: false,
        },
      ],
      name: 'DIRECT_MERGE',
      // This is returned, but not currently needed
      // allowableStatus: 'BLOCKED',
    },
  ],
}

type MergeConditionArguments = {
  result?: PullRequestMergeConditionResult
  message?: string
  ruleRollups?: RuleRollupPayload[] | null | undefined
  failedSubConditions?: FailingSubConditionPayload[] | null | undefined
  conflicts?: string[]
  isConflictResolvableInWeb?: boolean
  webEditorConflictResolution?: MergeConflictWebEditorResolution | null
}
/**
 * Returns a specific type of merge requirement condition
 */
export const mockMergeRequirementCondition: Record<
  MergeConditionType,
  (args?: MergeConditionArguments) => MergeConditionPayload
> = {
  PULL_REQUEST_STATE: ({result, message} = {}): MergeConditionPayload => ({
    type: 'PULL_REQUEST_STATE',
    displayName: 'Pull request state',
    description: 'Pull request must be open and not in draft mode in order to be merged',
    message: message ?? null,
    result: result ?? 'PASSED',
  }),
  PULL_REQUEST_REPO_STATE: ({result, message} = {}): MergeConditionPayload => ({
    type: 'PULL_REQUEST_REPO_STATE',
    displayName: 'Pull request repository state',
    description: 'The repository must be not archived or locked',
    message: message ?? null,
    result: result ?? 'PASSED',
  }),
  PULL_REQUEST_USER_STATE: ({result, message, failedSubConditions} = {}): MergeConditionPayload => ({
    type: 'PULL_REQUEST_USER_STATE',
    displayName: 'Pull request user state',
    description: 'The user must have push access to the repo and a verified email',
    message: message ?? null,
    result: result ?? 'PASSED',
    failedSubConditions: failedSubConditions ?? [],
  }),
  PULL_REQUEST_RULES: ({result, message, ruleRollups} = {}): MergeConditionPayload => ({
    type: 'PULL_REQUEST_RULES',
    displayName: 'Repo rules',
    description: 'Pull request repository rules',
    message:
      message ??
      'Changes must be made through the merge queue Missing successful active production deployment. Waiting on approval from at least one compliance team: my-cool-reviewers.',
    result: result ?? 'FAILED',
    ruleRollups: ruleRollups ?? [
      {
        ruleType: 'PULL_REQUEST',
        displayName: 'Require a pull request before merging',
        message: 'Waiting on approval from at least one compliance team: my-cool-reviewers.',
        result: 'FAILED',
        bypassable: false,
        metadata: {
          requiredReviewers: 1,
          requiresCodeowners: false,
          failureReasons: ['soc2_approval_process_required'],
        },
      },
      {
        ruleType: 'WORKFLOWS',
        displayName: 'Require workflows to pass before merging',
        message: '',
        result: 'PASSED',
        bypassable: true,
        metadata: null,
      },
      {
        ruleType: 'DELETION',
        displayName: 'Restrict deletions',
        message: '',
        result: 'PASSED',
        bypassable: false,
        metadata: null,
      },
      {
        ruleType: 'NON_FAST_FORWARD',
        displayName: 'Block force pushes',
        message: '',
        result: 'PASSED',
        bypassable: false,
        metadata: null,
      },
      {
        ruleType: 'REQUIRED_STATUS_CHECKS',
        displayName: 'Require status checks to pass',
        message: '',
        result: 'PASSED',
        bypassable: false,
        metadata: {
          statusCheckResults: [
            {
              context: 'job / job-name',
              integrationId: 12345,
              result: 'success',
            },
          ],
        },
      },
      {
        ruleType: 'AUTHORIZATION',
        displayName: 'Restrict who can push',
        message: '',
        result: 'PASSED',
        bypassable: false,
        metadata: null,
      },
    ],
  }),
  PULL_REQUEST_MERGE_CONFLICT_STATE: ({
    result,
    message,
    conflicts,
    isConflictResolvableInWeb,
    webEditorConflictResolution,
  } = {}): ConflictMergeConditionPayload => ({
    type: 'PULL_REQUEST_MERGE_CONFLICT_STATE',
    displayName: 'Pull request merge conflict state',
    description: 'The pull request must not have any unresolved merge conflicts',
    message: message ?? null,
    result: result ?? 'PASSED',
    conflicts: conflicts ?? [],
    isConflictResolvableInWeb: isConflictResolvableInWeb ?? true,
    webEditorConflictResolution,
  }),
  PULL_REQUEST_MERGE_METHOD: ({result, message} = {}): MergeConditionPayload => ({
    type: 'PULL_REQUEST_MERGE_METHOD',
    displayName: 'Pull request merge method',
    description: 'The selected merge method must be valid for the base repository.',
    message: message ?? null,
    result: result ?? 'PASSED',
  }),
  UNKNOWN: ({result, message} = {}): MergeConditionPayload => ({
    type: 'UNKNOWN',
    displayName: 'UNKNOWN MERGE CONDITION',
    description: '',
    message: message ?? null,
    result: result ?? 'PASSED',
  }),
}

/**
 * A default set of merge requirements - an escape hatch if mergeBoxMockData is too opinionated.
 */
export const defaultMergeRequirements: PullRequestMergeRequirementsPayload = {
  state: 'UNMERGEABLE',
  conditions: [
    mockMergeRequirementCondition.PULL_REQUEST_STATE(),
    mockMergeRequirementCondition.PULL_REQUEST_REPO_STATE(),
    mockMergeRequirementCondition.PULL_REQUEST_USER_STATE(),
    mockMergeRequirementCondition.PULL_REQUEST_RULES(),
    mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE(),
    mockMergeRequirementCondition.PULL_REQUEST_MERGE_METHOD(),
  ],
  defaultCommitAuthorEmail: 'monalisa@github.com',
  commitMessageHeadline: 'Merge pull request #12345 from github/prx/test-branch',
  commitMessageBody: 'My commit message body',
  possibleCommitAuthorEmails: [],
}

/**
 * Object containing the preset and common pull request states
 */
type PullRequestKind =
  | 'clean'
  | 'closedWithUserActionsAllowed'
  | 'closedWithoutUserActionsAllowed'
  | 'default'
  | 'draft'
  | 'isInMergeQueue'
  | 'mergedWithUserActionsAllowed'
  | 'noReviewsConflicts'
  | 'onlyOneDirectMergeMethodAllowed'
  | 'unknownGitMergeStatus'
  | 'withApprovingReviews'
  | 'withDirectMergeEnabled'
  | 'withMergeQueueEnabled'
  | 'withAllowableToBypassAndAutoMerge'
  | 'withPendingReviewRequestNoReviews'

/**
 * Object containing the preset and common pull request states
 */
const mockPullRequest: Record<PullRequestKind, JSONAPIPullRequestPayload> = {
  default: defaultPullRequest,
  draft: {...defaultPullRequest, isDraft: true},
  clean: {...defaultPullRequest, mergeStateStatus: 'CLEAN'},
  withDirectMergeEnabled: {
    ...defaultPullRequest,
    mergeQueue: null,
    viewerCanAddAndRemoveFromMergeQueue: false,
    viewerCanEnableAutoMerge: false,
    viewerMergeActions: [
      {
        allowableStatus: 'BLOCKED',
        mergeMethods: [
          {
            allowableStatus: 'BLOCKED',
            name: 'MERGE',
          },
          {
            allowableStatus: 'BLOCKED',
            name: 'SQUASH',
          },
          {
            allowableStatus: 'BLOCKED',
            name: 'REBASE',
          },
        ],
        name: 'MERGE_QUEUE',
      },
      {
        allowableStatus: 'ALLOWED',
        mergeMethods: [
          {
            allowableStatus: 'ALLOWED',
            name: 'MERGE',
          },
          {
            allowableStatus: 'ALLOWED',
            name: 'SQUASH',
          },
          {
            allowableStatus: 'ALLOWED',
            name: 'REBASE',
          },
        ],
        name: 'DIRECT_MERGE',
      },
    ],
  },
  withMergeQueueEnabled: {
    ...defaultPullRequest,
    mergeQueue: {url: 'https://github.localhost/monalisa/smile/queue'},
    viewerCanAddAndRemoveFromMergeQueue: true,
    viewerCanEnableAutoMerge: false,
    viewerMergeActions: [
      {
        allowableStatus: 'ALLOWED',
        mergeMethods: [
          {
            allowableStatus: 'ALLOWED',
            name: 'MERGE',
          },
          {
            allowableStatus: 'BLOCKED',
            name: 'SQUASH',
          },
          {
            allowableStatus: 'BLOCKED',
            name: 'REBASE',
          },
        ],
        name: 'MERGE_QUEUE',
      },
      {
        allowableStatus: 'BLOCKED',
        mergeMethods: [
          {
            allowableStatus: 'ALLOWED_WITH_BYPASS',
            name: 'MERGE',
          },
          {
            allowableStatus: 'ALLOWED_WITH_BYPASS',
            name: 'SQUASH',
          },
          {
            allowableStatus: 'ALLOWED_WITH_BYPASS',
            name: 'REBASE',
          },
        ],
        name: 'DIRECT_MERGE',
      },
    ],
  },
  closedWithUserActionsAllowed: {...defaultPullRequest, state: 'CLOSED', viewerCanDeleteHeadRef: true},
  closedWithoutUserActionsAllowed: {
    ...defaultPullRequest,
    state: 'CLOSED',
    viewerCanDeleteHeadRef: false,
    viewerCanRestoreHeadRef: false,
  },
  mergedWithUserActionsAllowed: {...defaultPullRequest, state: 'MERGED', viewerCanDeleteHeadRef: true},
  isInMergeQueue: {
    ...defaultPullRequest,
    isInMergeQueue: true,
    mergeQueue: {url: 'https://github.localhost/monalisa/smile/queue'},
    mergeQueueEntry: {
      position: 1,
      state: 'QUEUED',
      isLocked: false,
    },
    viewerCanAddAndRemoveFromMergeQueue: true,
  },
  onlyOneDirectMergeMethodAllowed: {
    ...defaultPullRequest,
    mergeQueue: null,
    viewerCanAddAndRemoveFromMergeQueue: false,
    viewerCanEnableAutoMerge: false,
    viewerMergeActions: [
      {
        allowableStatus: 'BLOCKED',
        mergeMethods: [
          {
            allowableStatus: 'BLOCKED',
            name: 'MERGE',
          },
          {
            allowableStatus: 'BLOCKED',
            name: 'SQUASH',
          },
          {
            allowableStatus: 'BLOCKED',
            name: 'REBASE',
          },
        ],
        name: 'MERGE_QUEUE',
      },
      {
        allowableStatus: 'ALLOWED',
        mergeMethods: [
          {
            allowableStatus: 'ALLOWED',
            name: 'MERGE',
          },
          {
            allowableStatus: 'BLOCKED',
            name: 'SQUASH',
          },
          {
            allowableStatus: 'BLOCKED',
            name: 'REBASE',
          },
        ],
        name: 'DIRECT_MERGE',
      },
    ],
  },
  withApprovingReviews: {
    ...defaultPullRequest,
    mergeStateStatus: 'CLEAN',
    latestOpinionatedReviews: [
      {
        id: 12345,
        authorCanPushToRepository: true,
        author: {
          login: 'collaborator',
          avatarUrl: 'https://avatars.githubusercontent.com/u/12345?v=4',
          name: 'collaborator',
          url: 'https://github.com/collaborator',
        },
        onBehalfOf: ['my-cool-team'],
        state: 'APPROVED',
      },
      {
        id: 12346,
        authorCanPushToRepository: true,
        author: {
          login: 'octocat',
          avatarUrl: 'https://avatars.githubusercontent.com/u/678910?v=4',
          name: 'octocat',
          url: 'https://github.com/octocat',
        },
        onBehalfOf: ['my-cool-team-reviewers'],
        state: 'APPROVED',
      },
    ],
  },
  unknownGitMergeStatus: {
    ...defaultPullRequest,
    mergeStateStatus: 'UNKNOWN',
  },
  noReviewsConflicts: {
    ...defaultPullRequest,
    pendingReviewRequests: [],
    latestOpinionatedReviews: [],
    mergeStateStatus: 'DIRTY',
  },
  withPendingReviewRequestNoReviews: {
    ...defaultPullRequest,
    latestOpinionatedReviews: [],
    pendingReviewRequests: [
      {
        reviewer: {
          login: 'betty',
          avatarUrl: 'https://avatars.githubusercontent.com/u/12345?v=4',
          name: 'Betty',
          url: '',
          type: 'USER',
        },
        isCodeOwner: false,
      },
    ],
  },
  withAllowableToBypassAndAutoMerge: {
    ...defaultPullRequest,
    viewerCanEnableAutoMerge: true,
    viewerMergeActions: [
      {
        allowableStatus: 'BLOCKED',
        mergeMethods: [
          {
            allowableStatus: 'BLOCKED',
            name: 'MERGE',
          },
          {
            allowableStatus: 'BLOCKED',
            name: 'SQUASH',
          },
          {
            allowableStatus: 'BLOCKED',
            name: 'REBASE',
          },
        ],
        name: 'MERGE_QUEUE',
      },
      {
        allowableStatus: 'ALLOWED',
        mergeMethods: [
          {
            allowableStatus: 'ALLOWED',
            name: 'MERGE',
          },
          {
            allowableStatus: 'ALLOWED',
            name: 'SQUASH',
          },
          {
            allowableStatus: 'ALLOWED',
            name: 'REBASE',
          },
        ],
        name: 'DIRECT_MERGE',
      },
    ],
  },
}

const defaultCommitData = {
  defaultCommitAuthorEmail: 'monalisa@github.com',
  commitMessageHeadline: 'Merge pull request #12345 from github/prx/test-branch',
  commitMessageBody: 'My commit message body',
  possibleCommitAuthorEmails: [],
}

export type MergeRequirementsKind =
  | 'changesRequested'
  | 'checksFailing'
  | 'checksPending'
  | 'default'
  | 'draftNotReadyForReview'
  | 'draftReadyForReview'
  | 'failingRulesAndMergeConflictState'
  | 'failingAuthRule'
  | 'mergeConflicts'
  | 'mergeable'
  | 'mergeableIfStatusesPass'
  | 'noRulesConfigured'
  | 'nonActionableFailure'
  | 'rebaseConflicts'
  | 'repoUnwritableState'
  | 'requiredStatusChecksExpected'
  | 'reviewsRequiredAndApprovingReviews'
  | 'selectedMergeMethodNotAllowed'
  | 'unableToMerge'
  | 'unknownNoConflicts'
  | 'userRequiresPushAccessToMerge'
  | 'userRequiresVerifiedEmail'
  | 'userCanPushButIsBlockedByAuthorizationPolicy'

/**
 * Object containing preset and common merge requirements states
 */
const mockMergeRequirements: Record<MergeRequirementsKind, PullRequestMergeRequirementsPayload> = {
  default: defaultMergeRequirements,
  nonActionableFailure: {
    state: 'UNMERGEABLE',
    conditions: [
      mockMergeRequirementCondition.PULL_REQUEST_STATE({result: 'FAILED'}),
      mockMergeRequirementCondition.PULL_REQUEST_REPO_STATE({result: 'FAILED'}),
      mockMergeRequirementCondition.PULL_REQUEST_USER_STATE({result: 'FAILED'}),
      mockMergeRequirementCondition.PULL_REQUEST_RULES({
        result: 'PASSED',
        ruleRollups: [
          {
            ruleType: 'PULL_REQUEST',
            displayName: 'Require a pull request before merging',
            message: null,
            result: 'PASSED',
            bypassable: false,
            metadata: {
              requiredReviewers: 0,
              requiresCodeowners: false,
              failureReasons: [],
            },
          },
          {
            ruleType: 'WORKFLOWS',
            displayName: 'Require workflows to pass before merging',
            message: '',
            result: 'PASSED',
            bypassable: true,
            metadata: null,
          },
          {
            ruleType: 'DELETION',
            displayName: 'Restrict deletions',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: null,
          },
          {
            ruleType: 'NON_FAST_FORWARD',
            displayName: 'Block force pushes',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: null,
          },
          {
            ruleType: 'REQUIRED_STATUS_CHECKS',
            displayName: 'Require status checks to pass',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: {
              statusCheckResults: [
                {
                  context: 'job / job-name',
                  integrationId: 12345,
                  result: 'success',
                },
              ],
            },
          },
        ],
      }),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_METHOD({result: 'PASSED'}),
    ],
    ...defaultCommitData,
  },
  draftReadyForReview: {
    state: 'UNMERGEABLE',
    conditions: [
      mockMergeRequirementCondition.PULL_REQUEST_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_REPO_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_USER_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_RULES({
        result: 'PASSED',
        ruleRollups: [
          {
            ruleType: 'PULL_REQUEST',
            displayName: 'Require a pull request before merging',
            message: null,
            result: 'FAILED',
            bypassable: false,
            metadata: {
              requiredReviewers: 0,
              requiresCodeowners: false,
              failureReasons: [],
            },
          },
          {
            ruleType: 'WORKFLOWS',
            displayName: 'Require workflows to pass before merging',
            message: '',
            result: 'PASSED',
            bypassable: true,
            metadata: null,
          },
          {
            ruleType: 'DELETION',
            displayName: 'Restrict deletions',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: null,
          },
          {
            ruleType: 'NON_FAST_FORWARD',
            displayName: 'Block force pushes',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: null,
          },
          {
            ruleType: 'REQUIRED_STATUS_CHECKS',
            displayName: 'Require status checks to pass',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: {
              statusCheckResults: [
                {
                  context: 'job / job-name',
                  integrationId: 12345,
                  result: 'success',
                },
              ],
            },
          },
        ],
      }),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_METHOD({result: 'PASSED'}),
    ],
    ...defaultCommitData,
  },
  draftNotReadyForReview: {
    state: 'UNMERGEABLE',
    conditions: [
      mockMergeRequirementCondition.PULL_REQUEST_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_REPO_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_USER_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_RULES({
        result: 'FAILED',
        ruleRollups: [
          {
            ruleType: 'PULL_REQUEST',
            displayName: 'Require a pull request before merging',
            message: null,
            result: 'FAILED',
            bypassable: false,
            metadata: {
              requiredReviewers: 0,
              requiresCodeowners: false,
              failureReasons: [],
            },
          },
          {
            ruleType: 'WORKFLOWS',
            displayName: 'Require workflows to pass before merging',
            message: '',
            result: 'PASSED',
            bypassable: true,
            metadata: null,
          },
          {
            ruleType: 'DELETION',
            displayName: 'Restrict deletions',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: null,
          },
          {
            ruleType: 'NON_FAST_FORWARD',
            displayName: 'Block force pushes',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: null,
          },
          {
            ruleType: 'REQUIRED_STATUS_CHECKS',
            displayName: 'Require status checks to pass',
            message: '',
            result: 'FAILED',
            bypassable: false,
            metadata: {
              statusCheckResults: [
                {
                  context: 'job / job-name',
                  integrationId: 12345,
                  result: 'success',
                },
                {
                  context: 'job 2 / job-name-2',
                  integrationId: 13368,
                  result: 'expected',
                },
                {
                  context: 'job 3 / job-name-3',
                  integrationId: 143211,
                  result: 'in_progress',
                },
              ],
            },
          },
        ],
      }),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_METHOD({result: 'PASSED'}),
    ],
    ...defaultCommitData,
  },
  mergeable: {
    state: 'MERGEABLE',
    conditions: [
      mockMergeRequirementCondition.PULL_REQUEST_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_REPO_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_USER_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_RULES({
        result: 'PASSED',
        ruleRollups: [
          {
            ruleType: 'PULL_REQUEST',
            displayName: 'Require a pull request before merging',
            message: null,
            result: 'PASSED',
            bypassable: false,
            metadata: {
              requiredReviewers: 0,
              requiresCodeowners: false,
              failureReasons: [],
            },
          },
          {
            ruleType: 'WORKFLOWS',
            displayName: 'Require workflows to pass before merging',
            message: '',
            result: 'PASSED',
            bypassable: true,
            metadata: null,
          },
          {
            ruleType: 'DELETION',
            displayName: 'Restrict deletions',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: null,
          },
          {
            ruleType: 'NON_FAST_FORWARD',
            displayName: 'Block force pushes',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: null,
          },
          {
            ruleType: 'REQUIRED_STATUS_CHECKS',
            displayName: 'Require status checks to pass',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: {
              statusCheckResults: [
                {
                  context: 'job / job-name',
                  integrationId: 12345,
                  result: 'success',
                },
              ],
            },
          },
        ],
      }),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_METHOD({result: 'PASSED'}),
    ],
    ...defaultCommitData,
  },
  mergeableIfStatusesPass: {
    state: 'MERGEABLE_IF_STATUSES_PASS',
    conditions: [
      mockMergeRequirementCondition.PULL_REQUEST_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_REPO_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_USER_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_RULES({
        result: 'PASSED',
        ruleRollups: [
          {
            ruleType: 'PULL_REQUEST',
            displayName: 'Require a pull request before merging',
            message: null,
            result: 'PASSED',
            bypassable: false,
            metadata: {
              requiredReviewers: 0,
              requiresCodeowners: false,
              failureReasons: [],
            },
          },
          {
            ruleType: 'WORKFLOWS',
            displayName: 'Require workflows to pass before merging',
            message: '',
            result: 'PASSED',
            bypassable: true,
            metadata: null,
          },
          {
            ruleType: 'DELETION',
            displayName: 'Restrict deletions',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: null,
          },
          {
            ruleType: 'NON_FAST_FORWARD',
            displayName: 'Block force pushes',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: null,
          },
        ],
      }),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_METHOD({result: 'PASSED'}),
    ],
    ...defaultCommitData,
  },
  checksPending: {
    state: 'UNMERGEABLE',
    conditions: [
      mockMergeRequirementCondition.PULL_REQUEST_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_REPO_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_USER_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_RULES({
        result: 'FAILED',
        ruleRollups: [
          {
            ruleType: 'PULL_REQUEST',
            displayName: 'Require a pull request before merging',
            message: null,
            result: 'PASSED',
            bypassable: false,
            metadata: {
              requiredReviewers: 0,
              requiresCodeowners: false,
              failureReasons: [],
            },
          },
          {
            ruleType: 'WORKFLOWS',
            displayName: 'Require workflows to pass before merging',
            message: '',
            result: 'PASSED',
            bypassable: true,
            metadata: null,
          },
          {
            ruleType: 'DELETION',
            displayName: 'Restrict deletions',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: null,
          },
          {
            ruleType: 'NON_FAST_FORWARD',
            displayName: 'Block force pushes',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: null,
          },
          {
            ruleType: 'REQUIRED_STATUS_CHECKS',
            displayName: 'Require status checks to pass',
            message: '2 of 3 required status checks have not succeeded: 2 expected',
            result: 'FAILED',
            bypassable: false,
            metadata: {
              statusCheckResults: [
                {
                  context: 'job / job-name',
                  integrationId: 12345,
                  result: 'success',
                },
                {
                  context: 'job 2 / job-name-2',
                  integrationId: 11365,
                  result: 'expected',
                },
                {
                  context: 'job 3 / job-name-3',
                  integrationId: 18311,
                  result: 'in_progress',
                },
              ],
            },
          },
        ],
      }),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_METHOD({result: 'PASSED'}),
    ],
    ...defaultCommitData,
  },
  checksFailing: {
    state: 'UNMERGEABLE',
    conditions: [
      mockMergeRequirementCondition.PULL_REQUEST_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_REPO_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_USER_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_RULES({
        result: 'FAILED',
        ruleRollups: [
          {
            ruleType: 'PULL_REQUEST',
            displayName: 'Require a pull request before merging',
            message: null,
            result: 'PASSED',
            bypassable: false,
            metadata: {
              requiredReviewers: 0,
              requiresCodeowners: false,
              failureReasons: [],
            },
          },
          {
            ruleType: 'WORKFLOWS',
            displayName: 'Require workflows to pass before merging',
            message: '',
            result: 'PASSED',
            bypassable: true,
            metadata: null,
          },
          {
            ruleType: 'DELETION',
            displayName: 'Restrict deletions',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: null,
          },
          {
            ruleType: 'NON_FAST_FORWARD',
            displayName: 'Block force pushes',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: null,
          },
          {
            ruleType: 'REQUIRED_STATUS_CHECKS',
            displayName: 'Require status checks to pass',
            message: '2 of 3 required status checks are failing.',
            result: 'FAILED',
            bypassable: false,
            metadata: {
              statusCheckResults: [
                {
                  context: 'job / job-name',
                  integrationId: 12345,
                  result: 'success',
                },
                {
                  context: 'job 2 / job-name-2',
                  integrationId: 11365,
                  result: 'failed',
                },
                {
                  context: 'job 3 / job-name-3',
                  integrationId: 18311,
                  result: 'failed',
                },
              ],
            },
          },
        ],
      }),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_METHOD({result: 'PASSED'}),
    ],
    ...defaultCommitData,
  },
  changesRequested: {
    state: 'UNMERGEABLE',
    conditions: [
      mockMergeRequirementCondition.PULL_REQUEST_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_REPO_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_USER_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_RULES({
        result: 'FAILED',
        ruleRollups: [
          {
            ruleType: 'PULL_REQUEST',
            displayName: 'Require a pull request before merging',
            message: null,
            result: 'FAILED',
            bypassable: false,
            metadata: {
              requiredReviewers: 1,
              requiresCodeowners: false,
              failureReasons: ['CHANGES_REQUESTED'],
            },
          },
          {
            ruleType: 'WORKFLOWS',
            displayName: 'Require workflows to pass before merging',
            message: '',
            result: 'PASSED',
            bypassable: true,
            metadata: null,
          },
          {
            ruleType: 'DELETION',
            displayName: 'Restrict deletions',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: null,
          },
          {
            ruleType: 'NON_FAST_FORWARD',
            displayName: 'Block force pushes',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: null,
          },
          {
            ruleType: 'REQUIRED_STATUS_CHECKS',
            displayName: 'Require status checks to pass',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: {
              statusCheckResults: [
                {
                  context: 'job / job-name',
                  integrationId: 12345,
                  result: 'success',
                },
              ],
            },
          },
        ],
      }),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_METHOD({result: 'PASSED'}),
    ],
    ...defaultCommitData,
  },
  repoUnwritableState: {
    state: 'UNMERGEABLE',
    conditions: [mockMergeRequirementCondition.PULL_REQUEST_REPO_STATE({result: 'FAILED'})],
    ...defaultCommitData,
  },
  rebaseConflicts: {
    state: 'UNMERGEABLE',
    conditions: [
      mockMergeRequirementCondition.PULL_REQUEST_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_REPO_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_USER_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_RULES({
        result: 'PASSED',
        ruleRollups: [
          {
            ruleType: 'PULL_REQUEST',
            displayName: 'Require a pull request before merging',
            message: null,
            result: 'PASSED',
            bypassable: false,
            metadata: {
              requiredReviewers: 0,
              requiresCodeowners: false,
              failureReasons: [],
            },
          },
          {
            ruleType: 'WORKFLOWS',
            displayName: 'Require workflows to pass before merging',
            message: '',
            result: 'PASSED',
            bypassable: true,
            metadata: null,
          },
          {
            ruleType: 'DELETION',
            displayName: 'Restrict deletions',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: null,
          },
          {
            ruleType: 'NON_FAST_FORWARD',
            displayName: 'Block force pushes',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: null,
          },
          {
            ruleType: 'REQUIRED_STATUS_CHECKS',
            displayName: 'Require status checks to pass',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: {
              statusCheckResults: [
                {
                  context: 'job / job-name',
                  integrationId: 12345,
                  result: 'success',
                },
              ],
            },
          },
        ],
      }),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({
        result: 'FAILED',
        conflicts: [],
        isConflictResolvableInWeb: true,
      }),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_METHOD({result: 'PASSED'}),
    ],
    ...defaultCommitData,
  },
  unknownNoConflicts: {
    state: 'UNKNOWN',
    conditions: [
      mockMergeRequirementCondition.PULL_REQUEST_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_REPO_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_USER_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_RULES({
        result: 'FAILED',
        ruleRollups: [
          {
            ruleType: 'PULL_REQUEST',
            displayName: 'Require a pull request before merging',
            message: null,
            result: 'PASSED',
            bypassable: false,
            metadata: {
              requiredReviewers: 0,
              requiresCodeowners: false,
              failureReasons: [],
            },
          },
          {
            ruleType: 'WORKFLOWS',
            displayName: 'Require workflows to pass before merging',
            message: '',
            result: 'PASSED',
            bypassable: true,
            metadata: null,
          },
          {
            ruleType: 'DELETION',
            displayName: 'Restrict deletions',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: null,
          },
          {
            ruleType: 'NON_FAST_FORWARD',
            displayName: 'Block force pushes',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: null,
          },
          {
            ruleType: 'REQUIRED_STATUS_CHECKS',
            displayName: 'Require status checks to pass',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: {
              statusCheckResults: [
                {
                  context: 'job / job-name',
                  integrationId: 12345,
                  result: 'success',
                },
              ],
            },
          },
        ],
      }),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_METHOD({result: 'PASSED'}),
    ],
    ...defaultCommitData,
  },
  reviewsRequiredAndApprovingReviews: {
    state: 'MERGEABLE',
    conditions: [
      mockMergeRequirementCondition.PULL_REQUEST_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_REPO_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_USER_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_RULES({
        result: 'PASSED',
        ruleRollups: [
          {
            ruleType: 'PULL_REQUEST',
            displayName: 'Require a pull request before merging',
            message: null,
            result: 'PASSED',
            bypassable: false,
            metadata: {
              requiredReviewers: 1,
              requiresCodeowners: false,
              failureReasons: [],
            },
          },
          {
            ruleType: 'WORKFLOWS',
            displayName: 'Require workflows to pass before merging',
            message: '',
            result: 'PASSED',
            bypassable: true,
            metadata: null,
          },
          {
            ruleType: 'DELETION',
            displayName: 'Restrict deletions',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: null,
          },
          {
            ruleType: 'NON_FAST_FORWARD',
            displayName: 'Block force pushes',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: null,
          },
          {
            ruleType: 'REQUIRED_STATUS_CHECKS',
            displayName: 'Require status checks to pass',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: {
              statusCheckResults: [
                {
                  context: 'job / job-name',
                  integrationId: 12345,
                  result: 'success',
                },
              ],
            },
          },
        ],
      }),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_METHOD({result: 'PASSED'}),
    ],
    ...defaultCommitData,
  },
  mergeConflicts: {
    state: 'UNMERGEABLE',
    conditions: [
      mockMergeRequirementCondition.PULL_REQUEST_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_REPO_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_USER_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_RULES({
        result: 'PASSED',
        ruleRollups: [
          {
            ruleType: 'PULL_REQUEST',
            displayName: 'Require a pull request before merging',
            message: null,
            result: 'PASSED',
            bypassable: false,
            metadata: {
              requiredReviewers: 0,
              requiresCodeowners: false,
              failureReasons: [],
            },
          },
          {
            ruleType: 'WORKFLOWS',
            displayName: 'Require workflows to pass before merging',
            message: '',
            result: 'PASSED',
            bypassable: true,
            metadata: null,
          },
          {
            ruleType: 'DELETION',
            displayName: 'Restrict deletions',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: null,
          },
          {
            ruleType: 'NON_FAST_FORWARD',
            displayName: 'Block force pushes',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: null,
          },
          {
            ruleType: 'REQUIRED_STATUS_CHECKS',
            displayName: 'Require status checks to pass',
            message: '',
            result: 'PASSED',
            bypassable: false,
            metadata: {
              statusCheckResults: [
                {
                  context: 'job / job-name',
                  integrationId: 12345,
                  result: 'success',
                },
              ],
            },
          },
        ],
      }),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({
        result: 'FAILED',
        conflicts: ['readme.md'],
        isConflictResolvableInWeb: true,
      }),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_METHOD({result: 'PASSED'}),
    ],
    ...defaultCommitData,
  },
  userRequiresPushAccessToMerge: {
    state: 'UNMERGEABLE',
    conditions: [
      mockMergeRequirementCondition.PULL_REQUEST_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_REPO_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_USER_STATE({
        result: 'FAILED',
        message: 'User is unable to merge this pull request.',
      }),
      mockMergeRequirementCondition.PULL_REQUEST_RULES({
        result: 'PASSED',
        ruleRollups: [],
      }),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({
        result: 'PASSED',
      }),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_METHOD({result: 'PASSED'}),
    ],
    ...defaultCommitData,
  },
  userRequiresVerifiedEmail: {
    state: 'UNMERGEABLE',
    conditions: [
      mockMergeRequirementCondition.PULL_REQUEST_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_REPO_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_USER_STATE({
        result: 'FAILED',
        message: 'User is unable to merge this pull request.',
        failedSubConditions: [
          {
            displayName: 'UNVERIFIED_EMAIL',
            message: 'Your email address must be verified before merging.',
          },
        ],
      }),
      mockMergeRequirementCondition.PULL_REQUEST_RULES({
        result: 'PASSED',
        ruleRollups: [],
      }),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({
        result: 'PASSED',
      }),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_METHOD({result: 'PASSED'}),
    ],
    ...defaultCommitData,
  },
  failingRulesAndMergeConflictState: {
    state: 'UNMERGEABLE',
    conditions: [
      mockMergeRequirementCondition.PULL_REQUEST_RULES({
        result: 'FAILED',
        message:
          // eslint-disable-next-line github/unescaped-html-literal
          '<div>At least one approving review is required by reviewers with write access. Missing successful deployment. Visit <a href="https://example.com">https://example.com</a> to learn more.</div>',
        ruleRollups: [
          {
            ruleType: 'PULL_REQUEST',
            result: 'FAILED',
            message:
              // eslint-disable-next-line github/unescaped-html-literal
              '<div>At least one approving review is required by reviewers with write access. Visit <a href="https://example.com">https://example.com</a> to learn more.</div>',
            displayName: 'Require a pull request before merging',
            bypassable: false,
            metadata: {
              requiredReviewers: 1,
              requiresCodeowners: false,
              failureReasons: ['MORE_REVIEWS_REQUIRED'],
            },
          },
          {
            ruleType: 'REQUIRED_DEPLOYMENTS',
            result: 'FAILED',
            message: 'Missing successful deployment.',
            displayName: 'Require deployments to succeed',
            bypassable: false,
            metadata: null,
          },
        ],
      }),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({
        result: 'FAILED',
        message: 'Pull request cannot be merged because it has a merge conflict.',
        conflicts: ['README.md'],
        isConflictResolvableInWeb: true,
      }),
    ],
    defaultCommitAuthorEmail: 'not-monalisa@github.com',
    commitMessageHeadline: 'Merge pull request #12345 from github/prx/test-branch',
    commitMessageBody: 'should be commiting on a merge',
    possibleCommitAuthorEmails: [],
  },
  failingAuthRule: {
    state: 'UNMERGEABLE',
    conditions: [
      mockMergeRequirementCondition.PULL_REQUEST_RULES({
        result: 'FAILED',
        message:
          // eslint-disable-next-line github/unescaped-html-literal
          '<div>You&#39;re not authorized to push to this branch. Visit <a href="https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches">https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches</a> for more information.</div>',
        ruleRollups: [
          {
            ruleType: 'AUTHORIZATION',
            result: 'FAILED',
            message:
              // eslint-disable-next-line github/unescaped-html-literal
              '<div>You&#39;re not authorized to push to this branch. Visit <a href="https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches">https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches</a> for more information.</div>',
            displayName: 'Restrict who can push',
            bypassable: false,
            metadata: null,
          },
        ],
      }),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({
        result: 'FAILED',
        message: 'Pull request cannot be merged because it has a merge conflict.',
        conflicts: ['README.md'],
        isConflictResolvableInWeb: true,
      }),
    ],
    defaultCommitAuthorEmail: 'not-monalisa@github.com',
    commitMessageHeadline: 'Merge pull request #12345 from github/prx/test-branch',
    commitMessageBody: 'should be commiting on a merge',
    possibleCommitAuthorEmails: [],
  },
  requiredStatusChecksExpected: {
    state: 'UNMERGEABLE',
    conditions: [
      mockMergeRequirementCondition.PULL_REQUEST_RULES({
        result: 'FAILED',
        message: 'Required status check "build" is expected.',
        ruleRollups: [
          {
            ruleType: 'REQUIRED_STATUS_CHECKS',
            displayName: 'Require status checks to pass',
            message: 'Required status check "build" is expected.',
            result: 'FAILED',
            bypassable: false,
            metadata: {
              statusCheckResults: [
                {
                  context: 'build',
                  integrationId: null,
                  result: 'expected',
                },
              ],
            },
          },
        ],
      }),
    ],
    ...defaultCommitData,
  },
  unableToMerge: {
    state: 'UNMERGEABLE',
    conditions: [
      mockMergeRequirementCondition.PULL_REQUEST_RULES({
        result: 'FAILED',
        message: 'Missing successful deployment.',
        ruleRollups: [
          {
            ruleType: 'PULL_REQUEST',
            result: 'PASSED',
            message: '',
            displayName: 'Require a pull request before merging',
            bypassable: false,
            metadata: {
              requiredReviewers: 0,
              requiresCodeowners: false,
              failureReasons: [],
            },
          },
          {
            ruleType: 'REQUIRED_DEPLOYMENTS',
            result: 'FAILED',
            message: 'Missing successful deployment.',
            displayName: 'Require deployments to succeed',
            bypassable: false,
            metadata: null,
          },
        ],
      }),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({result: 'PASSED'}),
    ],
    ...defaultCommitData,
  },
  selectedMergeMethodNotAllowed: {
    state: 'UNMERGEABLE',
    conditions: [
      mockMergeRequirementCondition.PULL_REQUEST_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_REPO_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_USER_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_METHOD({result: 'FAILED'}),
      mockMergeRequirementCondition.PULL_REQUEST_RULES({result: 'FAILED'}),
    ],
    ...defaultCommitData,
  },
  noRulesConfigured: {
    state: 'MERGEABLE',
    conditions: [
      mockMergeRequirementCondition.PULL_REQUEST_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_REPO_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_USER_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_RULES({result: 'PASSED', message: '', ruleRollups: []}),
    ],
    ...defaultCommitData,
  },
  userCanPushButIsBlockedByAuthorizationPolicy: {
    state: 'UNMERGEABLE',
    conditions: [
      mockMergeRequirementCondition.PULL_REQUEST_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_REPO_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_USER_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({result: 'PASSED'}),
      mockMergeRequirementCondition.PULL_REQUEST_RULES({
        result: 'FAILED',
        message:
          "You're not authorized to push to this branch. Visit https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches for more information.",
        ruleRollups: [
          {
            ruleType: 'AUTHORIZATION',
            displayName: 'Restrict who can push',
            message:
              "You're not authorized to push to this branch. Visit https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches for more information.",
            result: 'FAILED',
            bypassable: false,
            metadata: null,
          },
        ],
      }),
    ],
    ...defaultCommitData,
  },
}

type MergeActionName =
  | 'defaultDirectMerge'
  | 'directMergeWithBypassAllowed'
  | 'defaultMergeQueue'
  | 'mergeQueueWithBypassAllowed'
export const mockViewerMergeActions: Record<MergeActionName, ViewerMergeActions> = {
  defaultDirectMerge: [
    {
      name: MergeAction.DIRECT_MERGE,
      allowableStatus: 'ALLOWED',
      mergeMethods: [
        {
          name: MergeMethod.MERGE,
          allowableStatus: 'ALLOWED',
        },
        {
          name: MergeMethod.SQUASH,
          allowableStatus: 'ALLOWED',
        },
        {
          name: MergeMethod.REBASE,
          allowableStatus: 'ALLOWED',
        },
      ],
    },
    {
      name: MergeAction.MERGE_QUEUE,
      allowableStatus: 'BLOCKED',
      mergeMethods: [
        {
          name: MergeMethod.MERGE,
          allowableStatus: 'BLOCKED',
        },
      ],
    },
  ],
  directMergeWithBypassAllowed: [
    {
      name: MergeAction.DIRECT_MERGE,
      allowableStatus: 'ALLOWED',
      mergeMethods: [
        {
          name: MergeMethod.MERGE,
          allowableStatus: 'ALLOWED_WITH_BYPASS',
        },
        {
          name: MergeMethod.SQUASH,
          allowableStatus: 'ALLOWED',
        },
        {
          name: MergeMethod.REBASE,
          allowableStatus: 'ALLOWED_WITH_BYPASS',
        },
      ],
    },
    {
      name: MergeAction.MERGE_QUEUE,
      allowableStatus: 'BLOCKED',
      mergeMethods: [
        {
          name: MergeMethod.MERGE,
          allowableStatus: 'BLOCKED',
        },
      ],
    },
  ],
  defaultMergeQueue: [
    {
      name: MergeAction.DIRECT_MERGE,
      allowableStatus: 'BLOCKED',
      mergeMethods: [
        {
          name: MergeMethod.MERGE,
          allowableStatus: 'BLOCKED',
        },
        {
          name: MergeMethod.SQUASH,
          allowableStatus: 'BLOCKED',
        },
        {
          name: MergeMethod.REBASE,
          allowableStatus: 'BLOCKED',
        },
      ],
    },
    {
      name: MergeAction.MERGE_QUEUE,
      allowableStatus: 'ALLOWED',
      mergeMethods: [
        {
          name: MergeMethod.MERGE,
          allowableStatus: 'ALLOWED',
        },
      ],
    },
  ],
  mergeQueueWithBypassAllowed: [
    {
      name: MergeAction.DIRECT_MERGE,
      allowableStatus: 'BLOCKED',
      mergeMethods: [
        {
          name: MergeMethod.MERGE,
          allowableStatus: 'ALLOWED_WITH_BYPASS',
        },
        {
          name: MergeMethod.SQUASH,
          allowableStatus: 'ALLOWED_WITH_BYPASS',
        },
        {
          name: MergeMethod.REBASE,
          allowableStatus: 'ALLOWED_WITH_BYPASS',
        },
      ],
    },
    {
      name: MergeAction.MERGE_QUEUE,
      allowableStatus: 'ALLOWED',
      mergeMethods: [
        {
          name: MergeMethod.MERGE,
          allowableStatus: 'ALLOWED',
        },
      ],
    },
  ],
}

import {
  getConflictsCondition,
  getFailingGenericMergeConditions,
  getFailingRulesConditions,
  getFailingConditionsWithSubConditions,
  getReviewRuleRollupMetadata,
  isUserBlockedFromPushingByAuthorizationPolicy,
} from '../json-api-helpers'
import {mergeBoxMockData} from '../../test-utils/mocks/json-api-response.mock'

describe('getReviewRuleRollupMetadata', () => {
  test('returns the right metadata for the pull request rule rollup', () => {
    const reviewerRules = getReviewRuleRollupMetadata(mergeBoxMockData().mergeRequirements)
    expect(reviewerRules).toEqual([
      {requiredReviewers: 1, requiresCodeowners: false, failureReasons: ['SOC2_APPROVAL_PROCESS_REQUIRED']},
    ])
  })
})

describe('getConflictsCondition', () => {
  test('returns the conflict condition if it exists', () => {
    const conflictCondition = getConflictsCondition(mergeBoxMockData().mergeRequirements)
    expect(conflictCondition).toEqual({
      type: 'PULL_REQUEST_MERGE_CONFLICT_STATE',
      displayName: 'Pull request merge conflict state',
      description: 'The pull request must not have any unresolved merge conflicts',
      message: null,
      result: 'PASSED',
      conflicts: [],
      isConflictResolvableInWeb: true,
    })
  })
})

describe('getFailingGenericMergeConditions', () => {
  test('returns the failing merge conditions excluding the pull request rules condition', () => {
    const failingMergeConditions = getFailingGenericMergeConditions(
      mergeBoxMockData({mergeRequirementsKind: 'selectedMergeMethodNotAllowed'}).mergeRequirements,
    )
    expect(failingMergeConditions).toEqual([
      {
        type: 'PULL_REQUEST_MERGE_METHOD',
        displayName: 'Pull request merge method',
        description: 'The selected merge method must be valid for the base repository.',
        message: null,
        result: 'FAILED',
      },
    ])
  })
})

describe('getFailingRulesCondition', () => {
  test('returns the failing rules condition if it exists', () => {
    const failingRulesCondition = getFailingRulesConditions(mergeBoxMockData().mergeRequirements)
    expect(failingRulesCondition).toEqual([
      {
        type: 'PULL_REQUEST_RULES',
        displayName: 'Repo rules',
        description: 'Pull request repository rules',
        message:
          'Changes must be made through the merge queue Missing successful active production deployment. Waiting on approval from at least one compliance team: my-cool-reviewers.',
        result: 'FAILED',
        ruleRollups: [
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
      },
    ])
  })
})

describe('getFailingConditionsWithSubConditions', () => {
  test('returns the failing conditions with sub conditions if they exist', () => {
    const failingConditionsWithSubConditions = getFailingConditionsWithSubConditions(
      mergeBoxMockData({mergeRequirementsKind: 'userRequiresVerifiedEmail'}).mergeRequirements,
    )
    expect(failingConditionsWithSubConditions).toEqual([
      {
        description: 'The user must have push access to the repo and a verified email',
        displayName: 'Pull request user state',
        message: 'User is unable to merge this pull request.',
        result: 'FAILED',
        failedSubConditions: [
          {
            displayName: 'UNVERIFIED_EMAIL',
            message: 'Your email address must be verified before merging.',
          },
        ],
        type: 'PULL_REQUEST_USER_STATE',
      },
    ])
  })
})

describe('isUserBlockedFromPushingByAuthorizationPolicy', () => {
  test('returns true if the user is blocked by an authorization policy', () => {
    const {mergeRequirements} = mergeBoxMockData({
      mergeRequirementsKind: 'userCanPushButIsBlockedByAuthorizationPolicy',
    })

    expect(isUserBlockedFromPushingByAuthorizationPolicy(mergeRequirements)).toBe(true)
  })

  test('returns false if the user is not blocked by an authorization policy because one does not exist', () => {
    const {mergeRequirements} = mergeBoxMockData()

    expect(isUserBlockedFromPushingByAuthorizationPolicy(mergeRequirements)).toBe(false)
  })

  test('returns false if the user is not blocked by failing rules', () => {
    const {mergeRequirements} = mergeBoxMockData({mergeRequirementsKind: 'mergeable'})

    expect(isUserBlockedFromPushingByAuthorizationPolicy(mergeRequirements)).toBe(false)
  })
})

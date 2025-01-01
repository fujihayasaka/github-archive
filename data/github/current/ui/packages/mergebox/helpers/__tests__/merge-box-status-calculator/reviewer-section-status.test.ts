import {ConsolidatedReviewState} from '../../../components/sections/ReviewerSection'
import {mergeBoxMockData} from '../../../test-utils/mocks/json-api-response.mock'
import type {
  MergeStateStatus,
  PendingReviewRequest,
  PullRequestReviewState,
  PullRequestRuleFailureReason,
} from '../../../types'
import {getReviewsState, ReviewerSectionStatus} from '../../merge-box-status-calculator/reviewer-section-status'

describe('ReviewerSectionStatus', () => {
  test('returns correct status values when PR has reviews required and has approvals', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      mergeRequirementsKind: 'reviewsRequiredAndApprovingReviews',
    })

    const section = new ReviewerSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe(ConsolidatedReviewState.APPROVED)
    expect(section.mergeBoxStatus).toBe('PASSED')
    expect(section.numReviewsRequired).toBe(1)
    expect(section.consolidatedFailureReasons).toEqual([])
  })

  test('returns correct status values when PR has reviews required and does not have required approvals', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      mergeRequirementsKind: 'failingRulesAndMergeConflictState',
    })

    const section = new ReviewerSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe(ConsolidatedReviewState.REVIEW_REQUIRED)
    expect(section.mergeBoxStatus).toBe('NEUTRAL')
    expect(section.numReviewsRequired).toBe(1)
    expect(section.consolidatedFailureReasons).toEqual(['MORE_REVIEWS_REQUIRED'])
  })

  test('returns correct status values when PR has reviews required and changes requested', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      mergeRequirementsKind: 'changesRequested',
    })

    const section = new ReviewerSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe(ConsolidatedReviewState.CHANGES_REQUESTED)
    expect(section.mergeBoxStatus).toBe('FAILED')
    expect(section.numReviewsRequired).toBe(1)
    expect(section.consolidatedFailureReasons).toEqual(['CHANGES_REQUESTED'])
  })

  test('returns correct status values when PR does not require reviews and reviews were requested but no reviews were yet given', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'withPendingReviewRequestNoReviews',
      mergeRequirementsKind: 'noRulesConfigured',
    })

    const section = new ReviewerSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe(ConsolidatedReviewState.REVIEW_REQUESTED)
    expect(section.mergeBoxStatus).toBe('PASSED')
    expect(section.numReviewsRequired).toBe(0)
    expect(section.consolidatedFailureReasons).toEqual([])
  })

  test('returns correct status values when PR does not require reviews, no reviews were given, and there are no pending review requests', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'noReviewsConflicts',
      mergeRequirementsKind: 'noRulesConfigured',
    })

    const section = new ReviewerSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(false)
    expect(section.shouldConsiderStatus).toBe(false)
    expect(section.sectionStatus).toBe(ConsolidatedReviewState.REVIEWED)
    expect(section.mergeBoxStatus).toBe('PASSED')
    expect(section.numReviewsRequired).toBe(0)
    expect(section.consolidatedFailureReasons).toEqual([])
  })

  test('returns correct status values when PR does not require reviews and reviews were given', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'withApprovingReviews',
      mergeRequirementsKind: 'noRulesConfigured',
    })

    const section = new ReviewerSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe(ConsolidatedReviewState.REVIEWED)
    expect(section.mergeBoxStatus).toBe('PASSED')
    expect(section.numReviewsRequired).toBe(0)
    expect(section.consolidatedFailureReasons).toEqual([])
  })

  // See: https://github.com/github/pull-requests/issues/15479
  // This is a temporary workaround
  test('returns correct status values when PR has a merge conflict (and reviewer rules are not evaluated so it appears that no reviews are required', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'withPendingReviewRequestNoReviews',
      mergeRequirementsKind: 'noRulesConfigured',
    })

    const dirtyStatus: MergeStateStatus = 'DIRTY'
    const pullRequestWithMergeConflict = {...pullRequest, mergeStateStatus: dirtyStatus}

    const section = new ReviewerSectionStatus(pullRequestWithMergeConflict, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(false)
    expect(section.shouldConsiderStatus).toBe(false)
    expect(section.sectionStatus).toBe(ConsolidatedReviewState.REVIEW_REQUESTED)
    expect(section.mergeBoxStatus).toBe('PASSED')
    expect(section.numReviewsRequired).toBe(0)
    expect(section.consolidatedFailureReasons).toEqual([])
  })

  // See: https://github.com/github/pull-requests/issues/15479
  // This is a temporary workaround
  test("returns correct status values when the PR's git merge state is unknown (and reviewer rules are not evaluated so it appears that no reviews are required", () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'withPendingReviewRequestNoReviews',
      mergeRequirementsKind: 'noRulesConfigured',
    })

    const unknownStatus: MergeStateStatus = 'UNKNOWN'
    const pullRequestWithUnknownGitMergeState = {...pullRequest, mergeStateStatus: unknownStatus}
    const section = new ReviewerSectionStatus(pullRequestWithUnknownGitMergeState, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(false)
    expect(section.shouldConsiderStatus).toBe(false)
    expect(section.sectionStatus).toBe(ConsolidatedReviewState.REVIEW_REQUESTED)
    expect(section.mergeBoxStatus).toBe('PASSED')
    expect(section.numReviewsRequired).toBe(0)
    expect(section.consolidatedFailureReasons).toEqual([])
  })
})

describe('getReviewsState', () => {
  it('returns APPROVED when there are no failure reasons and at least one review', () => {
    const reviewsRequired = 1
    const isCodeownersRequired = false
    const reviews: Array<{readonly authorCanPushToRepository: boolean; readonly state: PullRequestReviewState}> = [
      {
        authorCanPushToRepository: false,
        state: 'APPROVED',
      },
    ]
    const failureReasons: PullRequestRuleFailureReason[] = []
    const pendingRequestedReviews: PendingReviewRequest[] = []

    expect(
      getReviewsState(reviewsRequired, isCodeownersRequired, reviews, failureReasons, pendingRequestedReviews),
    ).toBe(ConsolidatedReviewState.APPROVED)
  })

  it('returns APPROVED when there are no failure reasons and codeowners review is required', () => {
    const reviewsRequired = 0
    const isCodeownersRequired = true
    const reviews: Array<{readonly authorCanPushToRepository: boolean; readonly state: PullRequestReviewState}> = [
      {
        authorCanPushToRepository: false,
        state: 'APPROVED',
      },
    ]
    const failureReasons: PullRequestRuleFailureReason[] = []
    const pendingRequestedReviews: PendingReviewRequest[] = []

    expect(
      getReviewsState(reviewsRequired, isCodeownersRequired, reviews, failureReasons, pendingRequestedReviews),
    ).toBe(ConsolidatedReviewState.APPROVED)
  })

  it('returns REVIEW_REQUIRED when there are failure reasons that require more reviews', () => {
    const reviewsRequired = 2
    const isCodeownersRequired = false
    const reviews: Array<{readonly authorCanPushToRepository: boolean; readonly state: PullRequestReviewState}> = [
      {
        authorCanPushToRepository: false,
        state: 'APPROVED',
      },
    ]
    const failureReasons: PullRequestRuleFailureReason[] = ['MORE_REVIEWS_REQUIRED']
    const pendingRequestedReviews: PendingReviewRequest[] = []

    expect(
      getReviewsState(reviewsRequired, isCodeownersRequired, reviews, failureReasons, pendingRequestedReviews),
    ).toBe(ConsolidatedReviewState.REVIEW_REQUIRED)
  })

  it('returns REVIEW_REQUIRED when there are failure reasons that require codeowners review', () => {
    const reviewsRequired = 0
    const isCodeownersRequired = true
    const reviews: Array<{readonly authorCanPushToRepository: boolean; readonly state: PullRequestReviewState}> = [
      {
        authorCanPushToRepository: false,
        state: 'APPROVED',
      },
    ]
    const failureReasons: PullRequestRuleFailureReason[] = ['CODE_OWNER_REVIEW_REQUIRED']
    const pendingRequestedReviews: PendingReviewRequest[] = []

    expect(
      getReviewsState(reviewsRequired, isCodeownersRequired, reviews, failureReasons, pendingRequestedReviews),
    ).toBe(ConsolidatedReviewState.REVIEW_REQUIRED)
  })

  it('returns REVIEW_REQUIRED when there are failure reasons that require SOC2 approval process', () => {
    const reviewsRequired = 0
    const isCodeownersRequired = false
    const reviews: Array<{readonly authorCanPushToRepository: boolean; readonly state: PullRequestReviewState}> = [
      {
        authorCanPushToRepository: false,
        state: 'APPROVED',
      },
    ]
    const failureReasons: PullRequestRuleFailureReason[] = ['SOC2_APPROVAL_PROCESS_REQUIRED']
    const pendingRequestedReviews: PendingReviewRequest[] = []

    expect(
      getReviewsState(reviewsRequired, isCodeownersRequired, reviews, failureReasons, pendingRequestedReviews),
    ).toBe(ConsolidatedReviewState.REVIEW_REQUIRED)
  })

  it('returns CHANGES_REQUESTED when there are failure reasons that require changes', () => {
    const reviewsRequired = 0
    const isCodeownersRequired = false
    const reviews: Array<{readonly authorCanPushToRepository: boolean; readonly state: PullRequestReviewState}> = [
      {
        authorCanPushToRepository: false,
        state: 'APPROVED',
      },
    ]
    const failureReasons: PullRequestRuleFailureReason[] = ['CHANGES_REQUESTED']
    const pendingRequestedReviews: PendingReviewRequest[] = []

    expect(
      getReviewsState(reviewsRequired, isCodeownersRequired, reviews, failureReasons, pendingRequestedReviews),
    ).toBe(ConsolidatedReviewState.CHANGES_REQUESTED)
  })

  it('returns REVIEW_REQUIRED when there are failure reasons that require changes and more reviews', () => {
    const reviewsRequired = 2
    const isCodeownersRequired = false
    const reviews: Array<{readonly authorCanPushToRepository: boolean; readonly state: PullRequestReviewState}> = [
      {
        authorCanPushToRepository: false,
        state: 'APPROVED',
      },
    ]
    const failureReasons: PullRequestRuleFailureReason[] = ['CHANGES_REQUESTED', 'MORE_REVIEWS_REQUIRED']
    const pendingRequestedReviews: PendingReviewRequest[] = []

    expect(
      getReviewsState(reviewsRequired, isCodeownersRequired, reviews, failureReasons, pendingRequestedReviews),
    ).toBe(ConsolidatedReviewState.REVIEW_REQUIRED)
  })

  it('returns REVIEWED when there are no failure reasons and at least one review and no reviews are required', () => {
    const reviewsRequired = 0
    const isCodeownersRequired = false
    const reviews: Array<{readonly authorCanPushToRepository: boolean; readonly state: PullRequestReviewState}> = [
      {
        authorCanPushToRepository: false,
        state: 'APPROVED',
      },
    ]
    const failureReasons: PullRequestRuleFailureReason[] = []
    const pendingRequestedReviews: PendingReviewRequest[] = []

    expect(
      getReviewsState(reviewsRequired, isCodeownersRequired, reviews, failureReasons, pendingRequestedReviews),
    ).toBe(ConsolidatedReviewState.REVIEWED)
  })

  it('returns REVIEW_REQUESTED when review is not required, there have not been any reviews, and there is a review request', () => {
    const reviewsRequired = 0
    const isCodeownersRequired = false
    const reviews: Array<{readonly authorCanPushToRepository: boolean; readonly state: PullRequestReviewState}> = []
    const failureReasons: PullRequestRuleFailureReason[] = []
    const pendingRequestedReviews: PendingReviewRequest[] = [
      {
        reviewer: {
          login: 'monalisa',
          name: 'monalisa',
          avatarUrl: '',
          url: '',
          type: 'USER',
        },
        isCodeOwner: false,
      },
    ]

    expect(
      getReviewsState(reviewsRequired, isCodeownersRequired, reviews, failureReasons, pendingRequestedReviews),
    ).toBe(ConsolidatedReviewState.REVIEW_REQUESTED)
  })
})

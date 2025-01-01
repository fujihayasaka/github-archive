import {checksSectionRequiredChecksFailingAndPassingState} from '../../../test-utils/mocks/checks-section-mocks'
import {mergeBoxMockData} from '../../../test-utils/mocks/json-api-response.mock'
import {BlockedSectionStatus} from '../../merge-box-status-calculator/blocked-section-status'
import {ChecksSectionStatus} from '../../merge-box-status-calculator/checks-section-status'
import {ClosedOrMergedStateSectionStatus} from '../../merge-box-status-calculator/closed-or-merged-state-section-status'
import {ConflictsSectionStatus} from '../../merge-box-status-calculator/conflicts-section-status'
import {DraftStateSectionStatus} from '../../merge-box-status-calculator/draft-state-section-status'
import {MergeBoxStatusCalculator} from '../../merge-box-status-calculator/merge-box-status-calculator'
import {MergeQueueSectionStatus} from '../../merge-box-status-calculator/merge-queue-section-status'
import {ReviewerSectionStatus} from '../../merge-box-status-calculator/reviewer-section-status'

describe('MergeBoxStatusCalculator', () => {
  test('it returns the sections', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData()
    const calculator = new MergeBoxStatusCalculator(pullRequest, mergeRequirements, undefined)

    expect(calculator.sections.ClosedOrMergedStateMergeBox).toBeInstanceOf(ClosedOrMergedStateSectionStatus)
    expect(calculator.sections.DraftStateSection).toBeInstanceOf(DraftStateSectionStatus)
    expect(calculator.sections.MergeQueueSection).toBeInstanceOf(MergeQueueSectionStatus)
    expect(calculator.sections.ReviewerSection).toBeInstanceOf(ReviewerSectionStatus)
    expect(calculator.sections.BlockedSection).toBeInstanceOf(BlockedSectionStatus)
    expect(calculator.sections.ChecksSection).toBeInstanceOf(ChecksSectionStatus)
    expect(calculator.sections.ConflictsSection).toBeInstanceOf(ConflictsSectionStatus)
  })

  test('excludes sections that do not render from the calculation of the overall status, e.g. pull request is not a draft', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'clean',
      mergeRequirementsKind: 'noRulesConfigured',
    })
    const calculator = new MergeBoxStatusCalculator(pullRequest, mergeRequirements, undefined)

    expect(calculator.overallStatus).toBe('ALL_PASSED')
  })

  test('it returns the correct overall status when there are failing required status checks', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData()
    const calculator = new MergeBoxStatusCalculator(
      pullRequest,
      mergeRequirements,
      checksSectionRequiredChecksFailingAndPassingState,
    )

    expect(calculator.overallStatus).toBe('SOME_FAILED')
  })

  test('it returns the correct overall status when there are merge conflicts', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'noReviewsConflicts',
      mergeRequirementsKind: 'mergeConflicts',
    })
    const calculator = new MergeBoxStatusCalculator(pullRequest, mergeRequirements, undefined)

    expect(calculator.overallStatus).toBe('NEUTRAL')
  })

  test('it returns the correct overall status when the pull request is in draft and there are failing required checks', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'draft',
      mergeRequirementsKind: 'failingRulesAndMergeConflictState',
    })
    const calculator = new MergeBoxStatusCalculator(
      pullRequest,
      mergeRequirements,
      checksSectionRequiredChecksFailingAndPassingState,
    )

    expect(calculator.overallStatus).toBe('NEUTRAL')
  })

  test('it returns the correct overall status when there are any failures that appear in the blocked section and the current user can write', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      mergeRequirementsKind: 'failingRulesAndMergeConflictState',
    })
    const calculator = new MergeBoxStatusCalculator(pullRequest, mergeRequirements, undefined)

    expect(calculator.overallStatus).toBe('SOME_FAILED')
  })

  test('it returns the correct overall status when there are any failures that appear in the blocked section and the current user cannot write', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      mergeRequirementsKind: 'failingRulesAndMergeConflictState',
    })
    const pullRequestUserCannotWrite = {...pullRequest, viewerCanUpdate: false}
    const calculator = new MergeBoxStatusCalculator(pullRequestUserCannotWrite, mergeRequirements, undefined)

    expect(calculator.overallStatus).toBe('NEUTRAL')
  })

  test('it returns the correct overall status when everything has passed and the current user cannot write', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'withApprovingReviews',
      mergeRequirementsKind: 'mergeable',
    })
    const pullRequestUserCannotWrite = {...pullRequest, viewerCanUpdate: false}
    const calculator = new MergeBoxStatusCalculator(pullRequestUserCannotWrite, mergeRequirements, undefined)

    expect(calculator.overallStatus).toBe('ALL_PASSED')
  })

  test('it returns the correct overall status when everything has passed and the current user can write', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'withApprovingReviews',
      mergeRequirementsKind: 'mergeable',
    })
    const calculator = new MergeBoxStatusCalculator(pullRequest, mergeRequirements, undefined)

    expect(calculator.overallStatus).toBe('ALL_PASSED')
  })

  test('it returns the correct overall status when the pull request has been merged', () => {
    const {pullRequest} = mergeBoxMockData({
      pullRequestKind: 'mergedWithUserActionsAllowed',
    })
    const calculator = new MergeBoxStatusCalculator(pullRequest, null, undefined)

    expect(calculator.overallStatus).toBe('MERGED')
  })

  test('it returns the correct overall status when the pull request is closed', () => {
    const {pullRequest} = mergeBoxMockData({
      pullRequestKind: 'closedWithUserActionsAllowed',
    })
    const calculator = new MergeBoxStatusCalculator(pullRequest, null, undefined)

    expect(calculator.overallStatus).toBe('NEUTRAL')
  })

  test('it returns the correct overall status when the pull request is in the merge queue', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'isInMergeQueue',
    })
    const calculator = new MergeBoxStatusCalculator(pullRequest, mergeRequirements, undefined)

    expect(calculator.overallStatus).toBe('QUEUED')
  })
})

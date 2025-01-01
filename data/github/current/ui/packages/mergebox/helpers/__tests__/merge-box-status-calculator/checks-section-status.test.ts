import {
  checksSectionNonRequiredChecksFailingState,
  checksSectionNonRequiredChecksPassingState,
  checksSectionPendingAndWaitingState,
  checksSectionPendingApproval,
  checksSectionRequiredChecksFailingAndPassingState,
  checksSectionRequiredChecksFailingAndPendingState,
  checksSectionRequiredChecksPassingState,
} from '../../../test-utils/mocks/checks-section-mocks'
import {mergeBoxMockData} from '../../../test-utils/mocks/json-api-response.mock'
import type {MergeStateStatus} from '../../../types'
import {ChecksSectionStatus} from '../../merge-box-status-calculator/checks-section-status'

describe('ChecksSectionStatus', () => {
  test('returns correct values when the PR has failing required checks', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      mergeRequirementsKind: 'mergeableIfStatusesPass',
    })
    const statusChecks = checksSectionRequiredChecksFailingAndPassingState

    const section = new ChecksSectionStatus(pullRequest, mergeRequirements, statusChecks)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe('FAILED')
    expect(section.mergeBoxStatus).toBe('FAILED')
  })

  test('returns correct values when the PR has pending required checks', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      mergeRequirementsKind: 'checksPending',
    })
    const statusChecks = checksSectionPendingAndWaitingState

    const section = new ChecksSectionStatus(pullRequest, mergeRequirements, statusChecks)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe('PENDING')
    expect(section.mergeBoxStatus).toBe('PENDING')
  })

  test('returns correct values when the PR has pending and failing required checks', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      mergeRequirementsKind: 'checksPending',
    })
    const statusChecks = checksSectionRequiredChecksFailingAndPendingState

    const section = new ChecksSectionStatus(pullRequest, mergeRequirements, statusChecks)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe('PENDING')
    expect(section.mergeBoxStatus).toBe('PENDING')
  })

  test('returns correct values when the PR has pending required checks due to merge conflicts', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      mergeRequirementsKind: 'mergeConflicts',
    })
    const dirtyStatus: MergeStateStatus = 'DIRTY'
    const pullRequestWithConflict = {...pullRequest, mergeStateStatus: dirtyStatus}
    const statusChecks = checksSectionPendingAndWaitingState

    const section = new ChecksSectionStatus(pullRequestWithConflict, mergeRequirements, statusChecks)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe('PENDING_CONFLICTS')
    expect(section.mergeBoxStatus).toBe('PENDING')
  })

  test('returns correct values when the PR has rebase conflicts - i.e. checks will still run', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      mergeRequirementsKind: 'rebaseConflicts',
    })
    const cleanStatus: MergeStateStatus = 'CLEAN'
    const pullRequestClean = {...pullRequest, mergeStateStatus: cleanStatus}
    const statusChecks = checksSectionPendingAndWaitingState

    const section = new ChecksSectionStatus(pullRequestClean, mergeRequirements, statusChecks)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe('PENDING')
    expect(section.mergeBoxStatus).toBe('PENDING')
  })

  test('returns correct values when the PR has pending checks', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      mergeRequirementsKind: 'checksPending',
    })
    const statusChecks = checksSectionPendingAndWaitingState

    const section = new ChecksSectionStatus(pullRequest, mergeRequirements, statusChecks)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe('PENDING')
    expect(section.mergeBoxStatus).toBe('PENDING')
  })

  test('returns correct values when the PR has unsuccessful non-required checks', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      mergeRequirementsKind: 'unknownNoConflicts',
    })
    const statusChecks = checksSectionNonRequiredChecksFailingState

    const section = new ChecksSectionStatus(pullRequest, mergeRequirements, statusChecks)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe('FAILED')
    expect(section.mergeBoxStatus).toBe('NEUTRAL')
  })

  test('returns correct values when the PR has workflows pending approval', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData()
    const statusChecks = checksSectionPendingApproval

    const section = new ChecksSectionStatus(pullRequest, mergeRequirements, statusChecks)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe('PENDING_APPROVAL')
    expect(section.mergeBoxStatus).toBe('PENDING_USER_ACTION')
  })

  test('returns correct values when the PR has all passing required checks', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({mergeRequirementsKind: 'mergeable'})
    const statusChecks = checksSectionRequiredChecksPassingState

    const section = new ChecksSectionStatus(pullRequest, mergeRequirements, statusChecks)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe('PASSED')
    expect(section.mergeBoxStatus).toBe('PASSED')
  })

  test('returns correct values when the PR has all passing non-required checks', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({mergeRequirementsKind: 'mergeable'})
    const statusChecks = checksSectionNonRequiredChecksPassingState

    const section = new ChecksSectionStatus(pullRequest, mergeRequirements, statusChecks)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe('PASSED')
    expect(section.mergeBoxStatus).toBe('PASSED')
  })

  test('returns correct values when the PR does not have status check data', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({mergeRequirementsKind: 'mergeable'})

    const section = new ChecksSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(false)
    expect(section.shouldConsiderStatus).toBe(false)
    expect(section.sectionStatus).toBe('UNKNOWN')
    expect(section.mergeBoxStatus).toBe('NEUTRAL')
  })
})

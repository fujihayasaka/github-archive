import {mergeBoxMockData} from '../../../test-utils/mocks/json-api-response.mock'
import {ClosedOrMergedStateSectionStatus} from '../../merge-box-status-calculator/closed-or-merged-state-section-status'

describe('ClosedOrMergedStateSectionStatus', () => {
  test('returns correct status values when PR is closed', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'closedWithUserActionsAllowed',
    })

    const section = new ClosedOrMergedStateSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe('CLOSED')
    expect(section.mergeBoxStatus).toBe('NEUTRAL')
  })

  test('returns correct status values when PR is merged', () => {
    const {pullRequest: pullRequestData, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'mergedWithUserActionsAllowed',
    })
    const pullRequest = {...pullRequestData, viewerCanUpdate: false}

    const section = new ClosedOrMergedStateSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe('MERGED')
    expect(section.mergeBoxStatus).toBe('MERGED')
  })

  test('returns correct status values when PR is open', () => {
    const {pullRequest: pullRequestData, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'draft',
      mergeRequirementsKind: 'draftNotReadyForReview',
    })
    const pullRequest = {...pullRequestData, viewerCanUpdate: false}

    const section = new ClosedOrMergedStateSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(false)
    expect(section.shouldConsiderStatus).toBe(false)
    expect(section.sectionStatus).toBe('UNKNOWN')
    expect(section.mergeBoxStatus).toBe('NEUTRAL')
  })
})

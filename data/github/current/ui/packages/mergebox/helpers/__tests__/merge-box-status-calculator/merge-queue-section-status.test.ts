import {mergeBoxMockData} from '../../../test-utils/mocks/json-api-response.mock'
import {MergeQueueSectionStatus} from '../../merge-box-status-calculator/merge-queue-section-status'

describe('MergeQueueSectionStatus', () => {
  test('returns correct status values when PR in the merge queue', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'isInMergeQueue',
    })

    const section = new MergeQueueSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe('QUEUED')
    expect(section.mergeBoxStatus).toBe('QUEUED')
  })

  test('returns correct status values when PR is not in the merge queue', () => {
    const {pullRequest: pullRequestData, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'draft',
      mergeRequirementsKind: 'draftNotReadyForReview',
    })
    const pullRequest = {...pullRequestData, viewerCanUpdate: false}

    const section = new MergeQueueSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(false)
    expect(section.shouldConsiderStatus).toBe(false)
    expect(section.sectionStatus).toBe('QUEUED')
    expect(section.mergeBoxStatus).toBe('QUEUED')
  })
})

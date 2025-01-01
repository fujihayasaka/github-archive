import {mergeBoxMockData} from '../../../test-utils/mocks/json-api-response.mock'
import {BlockedSectionStatus} from '../../merge-box-status-calculator/blocked-section-status'

describe('BlockedSectionStatus', () => {
  test('returns correct status values when PR is mergeable', async () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'default',
      mergeRequirementsKind: 'mergeable',
    })

    const section = new BlockedSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(false)
    expect(section.shouldConsiderStatus).toBe(false)
    expect(section.sectionStatus).toBe('PASSED')
    expect(section.mergeBoxStatus).toBe('PASSED')
  })

  test('returns correct status values when PR is a draft', async () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'draft',
      mergeRequirementsKind: 'draftNotReadyForReview',
    })

    const section = new BlockedSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(false)
    expect(section.shouldConsiderStatus).toBe(false)
    expect(section.sectionStatus).toBe('FAILED')
    expect(section.mergeBoxStatus).toBe('FAILED')
  })

  test('returns correct status values when viewer cannot write to the repo', async () => {
    const {pullRequest: pullRequestData, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'default',
      mergeRequirementsKind: 'default',
    })

    const pullRequest = {...pullRequestData, viewerCanUpdate: false}
    const section = new BlockedSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(false)
    expect(section.shouldConsiderStatus).toBe(false)
    expect(section.sectionStatus).toBe('FAILED')
    expect(section.mergeBoxStatus).toBe('FAILED')
  })

  test('returns correct status values when PR is unmergeable', async () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'default',
      mergeRequirementsKind: 'default',
    })

    const section = new BlockedSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe('FAILED')
    expect(section.mergeBoxStatus).toBe('FAILED')
  })
})

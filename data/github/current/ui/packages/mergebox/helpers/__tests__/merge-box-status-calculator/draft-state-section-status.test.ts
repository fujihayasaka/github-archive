import {mergeBoxMockData} from '../../../test-utils/mocks/json-api-response.mock'
import type {PullRequestState} from '../../../types'
import {DraftStateSectionStatus} from '../../merge-box-status-calculator/draft-state-section-status'

describe('DraftStateSectionStatus', () => {
  test('returns correct status values when PR is a draft and viewerCanUpdate', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'draft',
      mergeRequirementsKind: 'draftNotReadyForReview',
    })

    const section = new DraftStateSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe('IS_DRAFT')
    expect(section.mergeBoxStatus).toBe('NEUTRAL')
  })

  test('returns correct status values when PR is a draft but viewerCanUpdate is false', () => {
    const {pullRequest: pullRequestData, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'draft',
      mergeRequirementsKind: 'draftNotReadyForReview',
    })
    const pullRequest = {...pullRequestData, viewerCanUpdate: false}

    const section = new DraftStateSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe('IS_DRAFT')
    expect(section.mergeBoxStatus).toBe('NEUTRAL')
  })

  test('returns correct status values when PR is not open but is a draft', () => {
    const {pullRequest: pullRequestData, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'draft',
      mergeRequirementsKind: 'draftNotReadyForReview',
    })
    const closedState: PullRequestState = 'CLOSED'
    const pullRequest = {...pullRequestData, state: closedState}

    const section = new DraftStateSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(false)
    expect(section.shouldConsiderStatus).toBe(false)
    expect(section.sectionStatus).toBe('IS_DRAFT')
    expect(section.mergeBoxStatus).toBe('NEUTRAL')
  })

  test('returns correct status values when PR is not a draft', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'default',
      mergeRequirementsKind: 'default',
    })

    const section = new DraftStateSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(false)
    expect(section.shouldConsiderStatus).toBe(false)
    expect(section.sectionStatus).toBe('IS_DRAFT')
    expect(section.mergeBoxStatus).toBe('NEUTRAL')
  })
})

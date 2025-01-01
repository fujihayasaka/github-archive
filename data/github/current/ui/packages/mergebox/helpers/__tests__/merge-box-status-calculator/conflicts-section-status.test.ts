import {mergeBoxMockData} from '../../../test-utils/mocks/json-api-response.mock'
import {ConflictsSectionStatus} from '../../merge-box-status-calculator/conflicts-section-status'

describe('ConflictsSectionStatus', () => {
  test('returns correct status values when PR BLOCKED and viewer cannot update branch', () => {
    const {pullRequest: pullRequestData, mergeRequirements} = mergeBoxMockData()
    const pullRequest = {...pullRequestData, viewerCanUpdateBranch: false}

    const section = new ConflictsSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(false)
    expect(section.shouldConsiderStatus).toBe(false)
    expect(section.sectionStatus).toBe('OUT_OF_DATE')
    expect(section.mergeBoxStatus).toBe('NEUTRAL')
  })

  test('returns correct status values when there are merge conflict conditions', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'noReviewsConflicts',
      mergeRequirementsKind: 'mergeConflicts',
    })

    const section = new ConflictsSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe('HAS_CONFLICTS')
    expect(section.mergeBoxStatus).toBe('NEUTRAL')
  })

  test('returns correct status values when clean', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'clean',
      mergeRequirementsKind: 'mergeable',
    })

    const section = new ConflictsSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe('NO_CONFLICTS')
    expect(section.mergeBoxStatus).toBe('PASSED')
  })

  test('returns correct status values when not BLOCKED and has rebase conflicts', () => {
    const {pullRequest, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'noReviewsConflicts',
      mergeRequirementsKind: 'rebaseConflicts',
    })

    const section = new ConflictsSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe('HAS_REBASE_CONFLICTS')
    expect(section.mergeBoxStatus).toBe('NEUTRAL')
  })

  test('returns correct status values when not BLOCKED and has advisory workspace', () => {
    const {pullRequest: pullRequestData, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'clean',
      mergeRequirementsKind: 'mergeable',
    })
    const pullRequest = {
      ...pullRequestData,
      advisoryWorkspace: {
        advisoryWorkspacePath: 'smile/monalisa/security/advisory/123',
        advisoryWorkspaceId: '123',
      },
    }
    const section = new ConflictsSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe('HAS_ADVISORY_WORKSPACE')
    expect(section.mergeBoxStatus).toBe('PASSED')
  })

  test('returns correct status values when DIRTY and has advisory workspace', () => {
    const {pullRequest: pullRequestData, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'noReviewsConflicts',
      mergeRequirementsKind: 'mergeConflicts',
    })
    const pullRequest = {
      ...pullRequestData,
      advisoryWorkspace: {
        advisoryWorkspacePath: 'smile/monalisa/security/advisory/123',
        advisoryWorkspaceId: '123',
      },
    }
    const section = new ConflictsSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe('HAS_CONFLICTS')
    expect(section.mergeBoxStatus).toBe('NEUTRAL')
  })

  test('returns correct status values when mergeStateStatus is UNKNOWN', () => {
    const {pullRequest: pullRequestData, mergeRequirements} = mergeBoxMockData({
      pullRequestKind: 'unknownGitMergeStatus',
      mergeRequirementsKind: 'default',
    })
    const pullRequest = {
      ...pullRequestData,
      advisoryWorkspace: {
        advisoryWorkspacePath: 'smile/monalisa/security/advisory/123',
        advisoryWorkspaceId: '123',
      },
    }
    const section = new ConflictsSectionStatus(pullRequest, mergeRequirements, undefined)
    expect(section.shouldRender).toBe(true)
    expect(section.shouldConsiderStatus).toBe(true)
    expect(section.sectionStatus).toBe('PENDING')
    expect(section.mergeBoxStatus).toBe('PENDING')
  })
})

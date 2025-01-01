import {renderHook} from '@testing-library/react'
import {useIssueState} from '../use-issue-state'

const mockUseFeatureFlags = jest.fn().mockReturnValue({})
jest.mock('@github-ui/react-core/use-feature-flag', () => ({
  useFeatureFlags: () => mockUseFeatureFlags({}),
}))

beforeEach(() => {
  mockUseFeatureFlags.mockClear()
})

describe('getStateQuery', () => {
  it('should return correct values when stateReason is COMPLETED', () => {
    const {result} = renderHook(() => useIssueState({state: 'CLOSED', stateReason: 'COMPLETED'}))
    const value = result.current.getStateQuery()
    expect(value).toEqual({
      stateChangeQuery: 'is:issue state:closed archived:false reason:completed',
      stateReasonString: 'completed',
    })
  })

  it('should return correct values when stateReason is NOT_PLANNED', () => {
    const {result} = renderHook(() => useIssueState({state: 'CLOSED', stateReason: 'NOT_PLANNED'}))
    const value = result.current.getStateQuery()
    expect(value).toEqual({
      stateChangeQuery: 'is:issue state:closed archived:false reason:not-planned',
      stateReasonString: 'not planned',
    })
  })

  it('should return correct values when stateReason is DUPLICATE', () => {
    mockUseFeatureFlags.mockReturnValue({issues_react_close_as_duplicate: true})
    const {result} = renderHook(() => useIssueState({state: 'CLOSED', stateReason: 'DUPLICATE'}))
    const value = result.current.getStateQuery()
    expect(value).toEqual({
      stateChangeQuery: 'is:issue state:closed archived:false reason:duplicate',
      stateReasonString: 'duplicate',
    })
  })

  it('should return correct values when stateReason is DUPLICATE and FF off', () => {
    mockUseFeatureFlags.mockReturnValue({issues_react_close_as_duplicate: false})
    const {result} = renderHook(() => useIssueState({state: 'CLOSED', stateReason: 'DUPLICATE'}))
    const value = result.current.getStateQuery()
    expect(value).toEqual({
      stateChangeQuery: 'is:issue state:closed archived:false reason:not-planned',
      stateReasonString: 'not planned',
    })
  })

  it('should return correct values when stateReason is REOPENED', () => {
    const {result} = renderHook(() => useIssueState({state: 'CLOSED', stateReason: 'REOPENED'}))
    const value = result.current.getStateQuery()
    expect(value).toEqual({
      stateChangeQuery: '',
      stateReasonString: 'reopened',
    })
  })
})

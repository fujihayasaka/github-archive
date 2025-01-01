import {renderHook} from '@testing-library/react'
import {useIssueState} from '../use-issue-state'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

jest.mock('@github-ui/react-core/use-feature-flag')
const mockUseFeatureFlag = jest.mocked(useFeatureFlag)

beforeEach(() => {
  mockUseFeatureFlag.mockReturnValue(false)
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
    const {result} = renderHook(() => useIssueState({state: 'CLOSED', stateReason: 'DUPLICATE'}))
    const value = result.current.getStateQuery()
    expect(value).toEqual({
      stateChangeQuery: 'is:issue state:closed archived:false reason:duplicate',
      stateReasonString: 'duplicate',
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

describe('sourceIcon', () => {
  it('should default to OPEN icon when PR state is undefined', () => {
    const {result} = renderHook(() => useIssueState({state: undefined, stateReason: null}))
    const value = result.current.sourceIcon('PullRequest')
    expect(value.name).toEqual('OPEN')
  })

  it('should default to OPEN icon when PR state is null', () => {
    const {result} = renderHook(() => useIssueState({state: null, stateReason: null}))
    const value = result.current.sourceIcon('PullRequest')
    expect(value.name).toEqual('OPEN')
  })

  it('should default to DRAFT icon when draft PR state is OPEN', () => {
    const isDraft = true
    const {result} = renderHook(() => useIssueState({state: 'OPEN', stateReason: null}))
    const value = result.current.sourceIcon('PullRequest', isDraft)
    expect(value.name).toEqual('DRAFT')
  })

  it('should default to CLOSED icon when draft PR state is CLOSED', () => {
    const isDraft = true
    const {result} = renderHook(() => useIssueState({state: 'CLOSED', stateReason: null}))
    const value = result.current.sourceIcon('PullRequest', isDraft)
    expect(value.name).toEqual('CLOSED')
  })
})

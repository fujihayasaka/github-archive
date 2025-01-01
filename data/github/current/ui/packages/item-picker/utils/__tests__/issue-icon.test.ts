import {IssueClosedIcon, IssueOpenedIcon, SkipIcon} from '@primer/octicons-react'
import {getIssueIconAndFill} from '../issue-icon'

describe('getIssueIconAndFill', () => {
  it('should return IssueOpenedIcon and open.fg when state is OPEN', () => {
    const result = getIssueIconAndFill('OPEN', null)
    expect(result).toEqual({icon: IssueOpenedIcon, fill: 'open.fg'})
  })

  it('should return IssueClosedIcon and done.fg when state is CLOSED and stateReason is COMPLETED', () => {
    const result = getIssueIconAndFill('CLOSED', 'COMPLETED')
    expect(result).toEqual({icon: IssueClosedIcon, fill: 'done.fg'})
  })

  it('should return SkipIcon and muted.fg when state is CLOSED and stateReason is not COMPLETED', () => {
    const result = getIssueIconAndFill('CLOSED', 'NOT_PLANNED')
    expect(result).toEqual({icon: SkipIcon, fill: 'muted.fg'})
  })

  it('should return SkipIcon and muted.fg when state is CLOSED and stateReason is not DUPLICATE', () => {
    const result = getIssueIconAndFill('CLOSED', 'DUPLICATE')
    expect(result).toEqual({icon: SkipIcon, fill: 'muted.fg'})
  })

  it('should return SkipIcon and muted.fg when state is CLOSED and stateReason is null', () => {
    const result = getIssueIconAndFill('CLOSED', null)
    expect(result).toEqual({icon: SkipIcon, fill: 'muted.fg'})
  })

  it('should return SkipIcon and muted.fg when state is CLOSED and stateReason is undefined', () => {
    const result = getIssueIconAndFill('CLOSED', undefined)
    expect(result).toEqual({icon: SkipIcon, fill: 'muted.fg'})
  })
})

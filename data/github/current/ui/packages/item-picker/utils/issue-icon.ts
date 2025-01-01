import {IssueClosedIcon, IssueOpenedIcon, SkipIcon} from '@primer/octicons-react'
import type {IssueState, IssueStateReason} from '../hooks/__generated__/useIssueFilteringFragment.graphql'

export function getIssueIconAndFill(state: IssueState, stateReason: IssueStateReason | null | undefined) {
  let icon = IssueOpenedIcon
  let fill = 'open.fg'

  if (state === 'CLOSED') {
    icon = stateReason === 'COMPLETED' ? IssueClosedIcon : SkipIcon
    fill = stateReason === 'COMPLETED' ? 'done.fg' : 'muted.fg'
  }

  return {icon, fill}
}

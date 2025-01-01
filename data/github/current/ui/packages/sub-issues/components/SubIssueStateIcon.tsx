import {graphql, useFragment} from 'react-relay'
import {NestedListItemLeadingVisual} from '@github-ui/nested-list-view/NestedListItemLeadingVisual'

import type {SubIssueStateIcon$key} from './__generated__/SubIssueStateIcon.graphql'
import {useIssueState} from '@github-ui/use-issue-state'

const stateIconFragment = graphql`
  fragment SubIssueStateIcon on Issue {
    state
    stateReason(enableDuplicate: true)
  }
`

type SubIssueStateIconProps = {
  dataKey: SubIssueStateIcon$key
}

export function SubIssueStateIcon({dataKey}: SubIssueStateIconProps) {
  const {state, stateReason} = useFragment(stateIconFragment, dataKey)
  const {sourceIcon} = useIssueState({state, stateReason})
  const SubIssueIcon = sourceIcon('Issue')

  return <NestedListItemLeadingVisual icon={SubIssueIcon} data-testid="nested-list-item-state-icon" />
}

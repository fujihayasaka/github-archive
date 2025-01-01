import {Box} from '@primer/react'
import {graphql} from 'relay-runtime'
import {useFragment} from 'react-relay'

import {AddSubIssueButtonGroup} from './AddSubIssueButtonGroup'
import {SubIssuesListView} from './SubIssuesListView'

import type {SubIssuesList$key} from './__generated__/SubIssuesList.graphql'
import type {SubIssueSidePanelItem} from '../types/sub-issue-types'

export function SubIssuesList({
  issueKey,
  onSubIssueClick,
  insideSidePanel,
  readonly = false,
}: {
  issueKey?: SubIssuesList$key
  onSubIssueClick?: (subIssueItem: SubIssueSidePanelItem) => void
  insideSidePanel?: boolean
  readonly?: boolean
}) {
  const subIssuesListData = useFragment(
    graphql`
      fragment SubIssuesList on Issue {
        ...SubIssuesListView
        ...AddSubIssueButtonGroup @arguments(fetchSubIssues: true)
      }
    `,
    issueKey,
  )

  return (
    <Box
      sx={{
        borderWidth: 1,
        borderStyle: 'solid',
        borderColor: 'border.default',
        borderRadius: 2,
        gap: 4,
      }}
    >
      <SubIssuesListView
        onSubIssueClick={onSubIssueClick}
        issueKey={subIssuesListData ?? undefined}
        readonly={readonly}
      />
      <Box sx={{p: 2}}>
        {subIssuesListData && !readonly && (
          <AddSubIssueButtonGroup issue={subIssuesListData} insideSidePanel={insideSidePanel} />
        )}
      </Box>
    </Box>
  )
}

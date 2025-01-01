import {graphql} from 'relay-runtime'
import {useFragment} from 'react-relay'

import {AddSubIssueButtonGroup} from './AddSubIssueButtonGroup'
import {SubIssuesListView} from './SubIssuesListView'

import type {SubIssuesList$key} from './__generated__/SubIssuesList.graphql'
import type {SubIssueSidePanelItem} from '../types/sub-issue-types'

import styles from './SubIssuesList.module.css'

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
    <div className={styles.Box}>
      <SubIssuesListView
        onSubIssueClick={onSubIssueClick}
        issueKey={subIssuesListData ?? undefined}
        readonly={readonly}
      />
      {subIssuesListData && !readonly && (
        <div className={styles.ButtonGroup}>
          <AddSubIssueButtonGroup issue={subIssuesListData} insideSidePanel={insideSidePanel} />
        </div>
      )}
    </div>
  )
}

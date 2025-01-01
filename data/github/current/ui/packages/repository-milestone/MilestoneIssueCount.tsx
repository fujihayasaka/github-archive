import {graphql, useFragment} from 'react-relay'
import type {MilestoneIssueCount$key} from './__generated__/MilestoneIssueCount.graphql'
import {LABELS} from './constants/labels'
import styles from './RepositoryMilestone.module.css'
import {useMemo} from 'react'

type MilestoneIssueCountProps = {
  milestone: MilestoneIssueCount$key
}

export function MilestoneIssueCount({milestone}: MilestoneIssueCountProps) {
  const currentMilestone = useFragment(
    graphql`
      fragment MilestoneIssueCount on Milestone {
        closedIssueCount
        openIssueCount
      }
    `,
    milestone,
  )

  const issueCounts = useMemo(() => {
    const openIssueCount = currentMilestone.openIssueCount ?? 0
    const closedIssueCount = currentMilestone.closedIssueCount ?? 0
    return {
      open: openIssueCount,
      closed: closedIssueCount,
      total: openIssueCount + closedIssueCount,
    }
  }, [currentMilestone.openIssueCount, currentMilestone.closedIssueCount])

  if (issueCounts.total <= 0) {
    return null
  }

  return (
    <div className={styles.milestoneIssueCount}>
      <span className={styles.middot}>{LABELS.separator}</span>
      <span>
        {issueCounts.closed}/{issueCounts.total} issues closed
      </span>
    </div>
  )
}

import {IssueClosedIcon, IssueOpenedIcon, SkipIcon} from '@primer/octicons-react'

export const VALUES = {
  issueIcons: {
    OPEN: {
      color: 'open.fg',
      icon: IssueOpenedIcon,
      description: 'Open issue',
    },
    CLOSED: {
      color: 'done.fg',
      icon: IssueClosedIcon,
      description: 'Closed issue (completed)',
    },
    NOT_PLANNED: {
      color: 'fg.muted',
      icon: SkipIcon,
      description: 'Closed issue (not planned)',
    },
  },
  issuesPageSize: 25,
  maxPrioritizableItemCount: 1000,
  milestonePageSize: 50,
  localStorageKeyBulkUpdateIssues: 'milestone.bulkUpdateIssues',
}

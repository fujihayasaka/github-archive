import {SkeletonText} from '@primer/react/experimental'
import {ListItemDescription} from '@github-ui/list-view/ListItemDescription'
import styles from '../DashboardLists.module.css'
import {ReplyIcon} from '@primer/octicons-react'

export interface IssueSummaryProps {
  isPending: boolean
  isError: boolean
  summary: string | undefined
  error: Error | null
}

export function IssueSummary({isPending, isError, summary, error}: IssueSummaryProps) {
  if (isPending) {
    return <SkeletonText data-testid="summary-skeleton-text" />
  }

  if (isError && error) {
    return <ListItemDescription>Something went wrong</ListItemDescription>
  }

  return (
    <ListItemDescription className={styles.description} data-testid="summary">
      <ReplyIcon size={16} className={styles.ReplyIcon} />
      {summary}
    </ListItemDescription>
  )
}

import {SkeletonText} from '@primer/react/experimental'
import {ListItemDescription} from '@github-ui/list-view/ListItemDescription'

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

  return <ListItemDescription data-testid="summary">{summary}</ListItemDescription>
}

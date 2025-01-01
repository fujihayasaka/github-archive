import {
  GitMergeIcon,
  GitMergeQueueIcon,
  GitPullRequestClosedIcon,
  GitPullRequestDraftIcon,
  GitPullRequestIcon,
  IssueClosedIcon,
  IssueOpenedIcon,
  SkipIcon,
  type Icon,
} from '@primer/octicons-react'

export const IssueStateIcons = {
  OPEN: ({className = '', ...props}) => (
    <IssueOpenedIcon aria-label="Open" {...props} className={`fgColor-open ${className}`} />
  ),
  COMPLETED: ({className = '', ...props}) => (
    <IssueClosedIcon aria-label="Completed" {...props} className={`fgColor-done ${className}`} />
  ),
  NOT_PLANNED: ({className = '', ...props}) => (
    <SkipIcon aria-label="Not planned" {...props} className={`fgColor-muted ${className}`} />
  ),
  DUPLICATE: ({className = '', ...props}) => (
    <SkipIcon aria-label="Duplicate" {...props} className={`fgColor-muted ${className}`} />
  ),
} as const satisfies Record<string, Icon>

export const PullRequestStateIcons = {
  MERGED: ({className = '', ...props}) => (
    <GitMergeIcon aria-label="Merged" {...props} className={`fgColor-done ${className}`} />
  ),
  IN_MERGE_QUEUE: ({className = '', ...props}) => (
    <GitMergeQueueIcon aria-label="In merge queue" {...props} className={`fgColor-attention ${className}`} />
  ),
  OPEN: ({className = '', ...props}) => (
    <GitPullRequestIcon aria-label="Open" {...props} className={`fgColor-open ${className}`} />
  ),
  CLOSED: ({className = '', ...props}) => (
    <GitPullRequestClosedIcon aria-label="Closed" {...props} className={`fgColor-closed ${className}`} />
  ),
  DRAFT: ({className = '', ...props}) => (
    <GitPullRequestDraftIcon aria-label="Draft" {...props} className={`fgColor-muted ${className}`} />
  ),
} as const satisfies Record<string, Icon>

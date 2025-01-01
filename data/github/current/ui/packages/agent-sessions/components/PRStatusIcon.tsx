import {
  GitMergeIcon,
  GitPullRequestClosedIcon,
  GitPullRequestDraftIcon,
  GitPullRequestIcon,
} from '@primer/octicons-react'

export function getPRStatusIcon(status: string) {
  switch (status) {
    case 'draft':
      return <GitPullRequestDraftIcon className="fgColor-muted" />
    case 'open':
      return <GitPullRequestIcon className="fgColor-open" />
    case 'closed':
      return <GitPullRequestClosedIcon className="fgColor-muted" />
    case 'merged':
      return <GitMergeIcon className="fgColor-done" />
    default:
      return <GitPullRequestIcon className="fgColor-open" />
  }
}

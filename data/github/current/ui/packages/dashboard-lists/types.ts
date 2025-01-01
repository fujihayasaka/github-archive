import type {RepositoryNWO} from '@github-ui/current-repository'

export type DashboardIssue = {
  id: string
  title: string
  description: string
  permalink: string
  commentCount: number
  comments: DashboardIssueComment[]
  updatedAt: string
  summary?: string
}

export type DashboardPullRequest = {
  author: string
  id: string
  title: string
  number: number
  permalink: string
  commentCount: number
  updatedAt: string
  suggestedAction: string
  headSha: string
  repoNameWithOwner: RepositoryNWO
  isDraft: boolean
  inMergeQueue: boolean
}

type DashboardIssueComment = {
  author: string
  body: string
}

export const PullRequestQueryQualifier = {
  Authored: 'author',
  Mentions: 'mentions',
  ReviewRequested: 'review-requested',
  ReviewedBy: 'reviewed-by',
} as const

export type PullRequestQueryQualifier = (typeof PullRequestQueryQualifier)[keyof typeof PullRequestQueryQualifier]

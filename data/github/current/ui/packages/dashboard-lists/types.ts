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
  id: string
  title: string
  permalink: string
  commentCount: number
  updatedAt: string
}

type DashboardIssueComment = {
  author: string
  body: string
}

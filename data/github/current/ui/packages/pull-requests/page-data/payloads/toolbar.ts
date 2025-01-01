export const PullRequestState = {
  Open: 'OPEN',
  Closed: 'CLOSED',
  Merged: 'MERGED',
} as const

export type PullRequestState = (typeof PullRequestState)[keyof typeof PullRequestState]

export type Repository = {
  id: number
  viewerPermission: string
}

export type AllowedNonCommentReviewType = 'APPROVE' | 'REQUEST_CHANGES'

export type PullRequest = {
  id: string
  pathName: string
  aliveChannel: string
  author: {
    login: string
  }
  repository: Repository
  state: PullRequestState
  viewerAllowedNonCommentReviewTypes: AllowedNonCommentReviewType[]
  viewerIsCopilotAttributed: boolean
  viewerHasViolatedPushPolicy: boolean
  comparison: {
    baseOid: string
    headOid: string
  }
}

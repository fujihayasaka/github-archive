import type {ThreadPreviewsPayload} from './thread-previews'
import type {AnnotationsPayload} from './annotations'
import type {ViewedFilesCountPayload} from './viewed-files-count'
import type {PendingReview} from './pending-review'

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

export type PullRequest = {
  id: string
  pathName: string
  aliveChannel: string
  author: {
    login: string
  }
  repository: Repository
  state: PullRequestState
  viewerCanLeaveNonCommentReviews: boolean
  viewerHasViolatedPushPolicy: boolean
  comparison: {
    baseOid: string
    headOid: string
  }
}

export type ToolbarPayload = {
  annotations: AnnotationsPayload
  copilotAccessAllowed: boolean
  currentUserLogin?: string
  isFileTreeExpanded: boolean
  pullRequest: PullRequest
  shouldShowViewedFilesCount: boolean
  // TODO update this possible "undefined" type when added to PullRequests::PageData::Files::Toolbar::Payload
  tabSize?: number
  threadPreviews: ThreadPreviewsPayload
  totalFilesCount: number
  viewedFilesCount: ViewedFilesCountPayload['viewedFilesCount']
  viewerPendingReview: PendingReview
}

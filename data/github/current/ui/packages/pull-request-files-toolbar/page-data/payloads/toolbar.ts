import type {DiffViewSettings} from '@github-ui/diff-view-settings/types'
import type {ThreadPreviewsPayload} from './thread-previews'
import type {AnnotationsPayload} from './annotations'
import type {ViewedFilesCountPayload} from './viewed-files-count'

export type PullRequest = {
  id: string
  pathName: string
  // TODO the remaining fields are not yet implemented in the payload coming from Rails
  // This simply keeps the code from breaking in the meantime on local development
  author: {
    login: string
  }
  headRefOid: string
  repository: {viewerPermission: string}
  state: string
  viewerCanLeaveNonCommentReviews: boolean
  viewerHasViolatedPushPolicy: boolean
  comparison: {
    newCommit: {oid: string}
  } | null
}

export type ToolbarPayload = {
  annotations: AnnotationsPayload
  copilotAccessAllowed: boolean
  hostUrl: string
  pullRequest: PullRequest
  repositoryId: string
  // TODO update this possible "undefined" type when added to PullRequests::PageData::Files::Toolbar::Payload
  tabSize?: number
  threadPreviews: ThreadPreviewsPayload
  totalFilesCount: number
  viewedFilesCount: ViewedFilesCountPayload['viewedFilesCount']
  viewSettings: DiffViewSettings
}

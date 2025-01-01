import type {FileTreePayload} from '@github-ui/pull-request-file-tree/PullRequestFileTreePayload'
import type {
  Repository,
  ToolbarPayload,
  PullRequest as ToolbarPullRequest,
} from '@github-ui/pull-request-files-toolbar/PullRequestToolbarPayload'
import type {HeaderPageData, HeaderRepository, User} from './header'
import type {DiffViewSettings} from '@github-ui/diff-view-settings/types'
import type {PullRequest} from '../../types'
import type {DiffEntry, DiffEntryData} from '@github-ui/diff-lines'

export type FilesRoutePayload = Pick<ToolbarPayload, 'annotations' | 'threadPreviews' | 'viewerPendingReview'> &
  Omit<HeaderPageData, 'pullRequest' | 'repository' | 'user'> & {
    commits: FileTreePayload['commits']
    diffContents: DiffContents[]
    diffSummaries: FileTreePayload['diffs']
    pullRequest: ToolbarPullRequest & PullRequest
    repository: HeaderRepository & Repository
    user: User & {
      currentUserLogin?: string
      isFileTreeExpanded: boolean
      lastReviewOid?: string
      shouldShowViewedFilesCount: boolean
      viewedFilesCount: number
      viewSettings: DiffViewSettings
    }
  }

// subset of DiffEntry returned by the API - we map in other shared fields from the rest of the payload as needed
export type DiffContents = DiffEntryData &
  Pick<DiffEntry, 'isBinary' | 'linesAdded' | 'linesDeleted' | 'richDiff' | 'diffSize' | 'reviewed'>

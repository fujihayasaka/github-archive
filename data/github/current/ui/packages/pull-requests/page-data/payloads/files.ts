import type {DiffEntry, DiffEntryData} from '@github-ui/diff-lines'
import type {DiffViewSettings} from '@github-ui/diff-view-settings/types'
import type {FileFilterState, FileFilterMenuOptions} from '../../components/diff-filtering/FileFilter'
import type {FileTreePayload, PullRequestFileTreeDiff} from './file-tree'
import type {Repository, PullRequest as ToolbarPullRequest} from './toolbar'
import type {PullRequest} from '../../types'
import type {Markers} from '../loaders/use-markers-data'
import type {HeaderPageData, HeaderRepository, User} from './header'
import type {ThreadPreviewsPayload} from './thread-previews'
import type {PendingReview} from './pending-review'
import type {Codeowners} from './codeowners'

export type PageLimits = {
  annotationsLimit: number
  annotationsLimitExceeded: boolean
  filesLimit: number
  filesLimitExceeded: boolean
  reviewThreadsLimit: number
  reviewThreadsLimitExceeded: boolean
}

export type FilesRoutePayload = Omit<HeaderPageData, 'pullRequest' | 'repository' | 'user'> & {
  codeowners?: Codeowners
  commits: FileTreePayload['commits']
  diffContents: DiffContents[]
  diffSummaries: PullRequestFileTreeDiff[]
  fileFilter: FileFilterPayload
  markers?: Markers
  pageLimits: PageLimits
  pullRequest: ToolbarPullRequest & PullRequest
  repository: HeaderRepository & Repository
  threadPreviews: ThreadPreviewsPayload
  user: User & {
    canComment: boolean
    commentingSettings: {
      emojiSkinTonePreference: number
      pasteUrlsAsPlainText: boolean
      useMonospaceFont: boolean
    }
    currentUserAvatarUrl?: string
    currentUserLogin?: string
    hasCopilotAccess: boolean
    canApplySuggestion: boolean
    isFileTreeExpanded: boolean
    lastReviewOid?: string
    shouldShowViewedFilesCount: boolean
    tabSize?: number
    viewSettings: DiffViewSettings
    viewedFilesCount: number
  }
  viewerPendingReview: PendingReview
}

type FileFilterPayload = {
  initialState: FileFilterState
  menuOptions: FileFilterMenuOptions
}

// subset of DiffEntry returned by the API - we map in other shared fields from the rest of the payload as needed
export type DiffContents = DiffEntryData &
  Pick<
    DiffEntry,
    | 'isBinary'
    | 'linesAdded'
    | 'linesDeleted'
    | 'richDiff'
    | 'diffSize'
    | 'reviewed'
    | 'commentingEnabled'
    | 'changeType'
  >

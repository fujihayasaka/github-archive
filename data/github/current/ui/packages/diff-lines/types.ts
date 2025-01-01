import type {DiffAnnotation} from '@github-ui/conversations'
import type {PatchStatus} from '@github-ui/diff-file-helpers'
import type {DiffLineType} from '@github-ui/diffs/types'
import type {FileRendererBlobData} from '@github-ui/file-renderer-blob'
import type {SafeHTMLString} from '@github-ui/safe-html'
import type {DiffMatchContent} from './diff-lines'
import type {CommentsPreference, DiffLineSpacingPreference, SplitPreference} from '@github-ui/diff-view-settings/types'
import type {StylingDirectivesLine} from '@github-ui/syntax-highlighted-lines/types'

export type {FileDiffReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'

//can add more contexts here in the future as needed
export type DiffContext = 'commit' | 'pr'

export type DiffEntryData = {
  readonly diffLines: DiffLine[]
  readonly isBinary: boolean
  readonly isTooBig: boolean
  readonly linesChanged: number
  readonly newTreeEntry:
    | {
        readonly isGenerated: boolean
        readonly lineCount: number | null | undefined
        readonly mode: number
        readonly path?: string | null | undefined
      }
    | null
    | undefined
  readonly newCommitOid?: string
  readonly objectId: string
  readonly oldTreeEntry:
    | {
        readonly lineCount: number | null | undefined
        readonly mode: number
        readonly path?: string | null | undefined
      }
    | null
    | undefined
  readonly oldCommitOid?: string
  readonly path: string
  readonly pathDigest: string
  readonly status: PatchStatus
  readonly truncatedReason: string | null | undefined
}

export type DiffLine = {
  readonly __id?: string
  readonly ast?: StylingDirectivesLine
  readonly left: number | null
  readonly right: number | null
  readonly blobLineNumber: number
  readonly displayNoNewLineWarning?: boolean
  readonly position?: number | null
  readonly type: DiffLineType
  readonly html: string
  readonly text: string
  threadsData?: ThreadsData
  annotationsData?: {
    readonly totalCount: number
    readonly annotations: ReadonlyArray<DiffAnnotation | null> | null
  }
}

export type ThreadsData = {
  readonly __id?: string
  readonly totalCommentsCount: number
  readonly totalCount: number
  readonly threads: ReadonlyArray<Thread | null> | null
}

export type Thread = {
  readonly id: string
  readonly isOutdated: boolean
  readonly commentsData: Comments
  readonly diffSide: DiffSide | null
  readonly line?: number | null
  readonly startDiffSide?: DiffSide | null
  readonly startLine?: number | null
}

export type Comments = {
  readonly __id?: string
  readonly totalCount: number
  readonly comments: ReadonlyArray<Comment | null> | null
}

export type Comment = {
  readonly id?: number
  readonly author: CommentAuthor | null
}

export type CommentAuthor = {
  avatarUrl: string
  login: string
  url: string
}

export const EMPTY_DIFF_LINE = 'empty-diff-line'
export type EmptyDiffLine = 'empty-diff-line'

export type ClientDiffLine = DiffLine | EmptyDiffLine

export type DiffSide = 'LEFT' | 'RIGHT'

export interface LineRange {
  diffAnchor: string
  endLineNumber: number
  endOrientation: 'left' | 'right'
  startLineNumber: number
  firstSelectedLineNumber: number
  firstSelectedOrientation: 'left' | 'right'
  startOrientation: 'left' | 'right'
}

export type RichDiff = {
  readonly canToggleRichDiff: boolean
  readonly defaultToRichDiff: boolean
  readonly proseDiffHtml?: SafeHTMLString
  readonly renderInfo?: FileRendererBlobData
  readonly dependencyDiffPath?: string
}

export type SubmoduleDiff = {
  /** The file path of the submodule in the current repo */
  basePath: string
  /**
   * The url to the submodule root
   *
   * This can be a repo, gist, wiki, or non-GitHub URL
   */
  submoduleUrl?: string
  /**
   * The url to the contents of the submodule if it is GH-hosted
   * This is used for linkable sha changes or to build compare URLs for submodule files when the diff summary is available
   *
   * This can be a GH repo, gist, wiki, or tree URL
   */
  contentsUrl?: string
  changedFiles?: number
  oldCommitOid?: string
  newCommitOid?: string
  status: PatchStatus
  summary: SummaryDelta[]
}

export type SummaryDelta = {
  linesAdded: number
  linesDeleted: number
  path: string
  pathDigest: string
  status: PatchStatus
}

// eslint-disable-next-line unused-imports/no-unused-vars
const STATE_LABEL_DATA = {
  OPEN: {
    description: 'Open',
    status: 'pullOpened',
  },
  CLOSED: {
    description: 'Closed',
    status: 'pullClosed',
  },
  QUEUED: {
    description: 'Queued',
    status: 'pullQueued',
  },
  MERGED: {
    description: 'Merged',
    status: 'pullMerged',
  },
  DRAFT: {
    description: 'Draft',
    status: 'draft',
  },
}

export type PullRequestState = keyof typeof STATE_LABEL_DATA

// The subject of the comment
// e.g. PullRequest or a Commit
export type Subject = {
  isInMergeQueue?: boolean
  state?: string
}

interface PullRequest {
  author: {
    login: string
  }
  aliveChannel: string
  baseBranch: string
  pathName: string
  commitsCount: number
  headBranch: string
  headRepositoryName?: string
  headRepositoryOwnerLogin?: string
  isInAdvisoryRepo: boolean
  mergedBy?: string
  mergedTime?: string
  number: number
  state: PullRequestState
  title: string
  titleHtml: SafeHTMLString
  url: string
  globalRelayId: string
  subject?: Subject | undefined
}

export type DiffEntry = DiffEntryData & {
  diffContext?: DiffContext
  diffMatches?: DiffMatchContent[]
  isSubmodule?: boolean
  richDiff?: RichDiff
  submodule?: SubmoduleDiff
  helpUrl: string
  diffSize: string
  linesAdded: number
  linesDeleted: number
  // TODO: Use PullRequest type from Pull Requests package and remove circular dependency
  pullRequest?: PullRequest
  commentingEnabled: boolean
  changeType: string
  collapsed?: boolean
  reviewed?: boolean
}

export type DiffUser = {
  avatarURL: string
  canComment: boolean
  canApplySuggestion: boolean
  commentsPreference: CommentsPreference
  hasCopilotAccess: boolean
  lineSpacing: DiffLineSpacingPreference
  login: string
  splitPreference: SplitPreference
  tabSize: number | undefined
}

import type {CommentBoxConfig} from '@github-ui/comment-box/CommentBox'
import type {RepoSubject} from '@github-ui/comment-box/subject'
import type {CommentSubjectTypes} from '@github-ui/commenting/CommentHeader'
import type {CommentAuthorAssociation as GraphQlCommentAuthorAssociation} from '@github-ui/commenting/IssueCommentHeader.graphql'
import type {DiffLine, LineRange} from '@github-ui/diff-lines'
import type {CommentsPreference} from '@github-ui/diff-view-settings/page-data/payloads/diff-view-settings'
import type {DiffLineType} from '@github-ui/diffs/types'
import type {ReactionContent, ReactionViewerGroup} from '@github-ui/reaction-viewer/ReactionGroupsUtils'
import type {FragmentRefs} from 'relay-runtime'

// TODO: rename this to be AnnotationLevel in a future PR to match ENUM on Rails.
// Plural name for ENUM is an odd convention.
export const DiffAnnotationLevels = {
  Failure: 'FAILURE',
  Notice: 'NOTICE',
  Warning: 'WARNING',
} as const

export type DiffAnnotationLevels = (typeof DiffAnnotationLevels)[keyof typeof DiffAnnotationLevels]

export type AnnotationCheckRun = {
  detailsUrl: string
  name: string
}

export type DiffAnnotation = {
  annotationLevel: DiffAnnotationLevels
  appAvatarUrl: string
  appAvatarAltText: string
  checkRun: AnnotationCheckRun
  checkSuiteName: string | null
  databaseId: number
  endLine: number
  id: string
  message: string
  path: string
  pathDigest: string
  startLine: number
  title: string
}

export type DiffSide = 'LEFT' | 'RIGHT'

export type SuggestedChangeLineRange = {
  endLineNumber: number
  endOrientation: DiffSide
  startLineNumber: number
  startOrientation: DiffSide
}

export type SuggestedChange = {
  authorLogin: string
  commentId: string
  path: string
  suggestion: string[]
  threadId: number | null | undefined
  lineRange: SuggestedChangeLineRange
}

export type ApplySuggestedChangesValidationData = {
  lineRange?: SuggestedChangeLineRange
}

export type CommentingImplementation = {
  batchingEnabled: boolean
  multilineEnabled: boolean
  resolvingEnabled: boolean
  pendingSuggestedChangesBatch: SuggestedChange[]
  suggestedChangesEnabled: boolean
  lazyFetchReactionGroups: boolean

  // submit single suggested change callback
  submitSuggestedChanges: (args: {
    commitMessage: string
    suggestedChanges: SuggestedChange[]
    onError: (error: Error, type?: string, friendlyMessage?: string) => void
    onCompleted?: () => void
  }) => void
  // add suggested change to pending batch callback
  addSuggestedChangeToPendingBatch: (suggestedChange: SuggestedChange) => void
  // remove suggested change from pending batch callback
  removeSuggestedChangeFromPendingBatch: (suggestedChange: SuggestedChange) => void
  // thread mutation callbacks
  addThread: (args: {
    diffLine?: DiffLine
    filePath: string
    isLeftSide?: boolean
    isLineSelected?: boolean
    onCompleted?: (threadId: string, commentDatabaseId?: number) => void
    onError: (error: Error) => void
    selectedDiffRowRange?: LineRange
    submitBatch?: boolean
    text: string
    /**
     * Relay-specific field that allows us to update relay store
     */
    threadsConnectionId?: string
  }) => void
  addThreadReply: (args: {
    /**
     * Relay-specific field that allows us to update relay store
     */
    commentsConnectionIds?: string[]
    filePath: string
    onCompleted?: (commentDatabaseId?: number) => void
    onError: (error: Error) => void
    submitBatch?: boolean
    text: string
    thread: Thread
    /**
     * Relay-specific field that allows us to update relay store
     */
    threadsConnectionId?: string
  }) => void
  addFileLevelThread: (args: {
    filePath: string
    onCompleted?: (threadId: string, commentDatabaseId?: number) => void
    onError: (error: Error) => void
    submitBatch?: boolean
    text: string
    /**
     * Relay-specific field that allows us to update relay store
     */
    threadsConnectionId?: string
  }) => void
  deleteComment: (args: {
    commentConnectionId?: string
    commentId: string
    filePath: string
    onCompleted?: () => void
    onError: (error: Error) => void
    threadCommentCount?: number
    threadsConnectionId?: string
    threadId: string
  }) => void
  editComment: (args: {
    comment: Comment
    onCompleted?: () => void
    onError: (error: Error) => void
    text: string
  }) => void
  hideComment: (args: {
    commentDatabaseId: number | null | undefined
    reason: string
    onCompleted?: () => void
    onError: (error: Error) => void
  }) => void
  unhideComment: (args: {
    commentDatabaseId: number | null | undefined
    onCompleted?: () => void
    onError: (error: Error) => void
  }) => void
  resolveThread: (args: {onCompleted?: () => void; onError: (error: Error) => void; threadId: string}) => void
  unresolveThread: (args: {onCompleted?: () => void; onError: (error: Error) => void; threadId: string}) => void
  reactToComment?: (args: {
    commentDatabaseId: number | null | undefined
    threadId: string
    reaction: ReactionContent
    viewerHasReacted: boolean
    onCompleted?: () => void
    onError: (error: Error) => void
  }) => void
  blockUserFromOrg?: (args: {
    duration: string
    shouldHideComment: boolean
    hiddenReason: string | undefined
    organizationLogin: string
    notifyBlockedUser: boolean
    userLogin: string
    onCompleted?: () => void
    onError: (error: Error) => void
  }) => void
  unblockUserFromOrg?: (args: {
    organizationLogin: string
    userLogin: string
    onCompleted?: () => void
    onError: (error: Error) => void
  }) => void

  // data fetching
  fetchThread: (threadId: string, includeAssociatedDiffLines?: boolean) => Promise<Thread | undefined>

  /**
   * When the thread data is changed, should the ui refetch the data? Should be used sparingly for specifc updates
   * that can happen in multiple places
   *
   * @param currentThread The current thread data of the review thread UI
   */
  shouldRefetchThread?: (currentThread: Thread) => boolean

  // comment box presentation
  commentBoxConfig: CommentBoxConfig

  /**
   * The type of the subject that comments are associated to.
   * Used to determine the correct reference tooltip text to display.
   */
  commentSubjectType?: CommentSubjectTypes

  /**
   * Markdown subject for the comment box. This is used to determine the context of the comment.
   * For example, when a RepoSubject is provided, features such as image upload, mentions, and emojis are enabled.
   * Pass in `undefined` if not providing a subject.
   * We require an explicit subject value or `undefined` to avoid implicit feature opt-outs.
   */
  commentBoxSubject: RepoSubject | undefined
}

export type Thread = {
  commentsData: Comments
  diffSide?: DiffSide
  id: string
  isOutdated?: boolean
  isResolved?: boolean
  subject?: ThreadSubject
  viewerCanReply?: boolean
  subjectType?: 'LINE' | 'FILE'
  // Optional because we try to construct threads from commit comments
  // and commit comments do not have this limit in place
  reviewCommentsLimit?: number
  reviewCommentsLimitExceeded?: boolean
}

export type ThreadSubject = {
  diffLines?: StaticDiffLine[]
  endLine?: number | null
  endDiffSide?: DiffSide
  originalEndLine?: number | null
  originalStartLine?: number | null
  pullRequestCommit?: {
    commit: {
      abbreviatedOid: string
    }
  }
  startDiffSide?: DiffSide | null
  startLine?: number | null
}

export type StaticDiffLine = {
  __id: string
  left: number | null
  right: number | null
  type: DiffLineType
  html: string
  text: string
}

export const CommentReviewVariantType = {
  Vanilla: 'vanilla',
  CodeScanning: 'code_scanning',
  Copilot: 'copilot',
  Dependabot: 'dependabot',
  CodeQuality: 'code_quality',
} as const

export type CommentReviewVariantType = (typeof CommentReviewVariantType)[keyof typeof CommentReviewVariantType]

export type Comments = {
  comments: Comment[]
  __id?: string
}

export type Comment = {
  author: Author | null | undefined
  authorAssociation: GraphQlCommentAuthorAssociation
  body: string
  bodyHTML: string
  bodyVersion?: string
  createdAt: string
  publishedAt: string | null | undefined
  currentDiffResourcePath?: string | null
  id: string
  databaseId: number | null | undefined
  isHidden: boolean
  lastUserContentEdit: UserContentEdit | null | undefined
  minimizedReason: string | null | undefined
  outdated?: boolean
  reactionGroups?: ReactionViewerGroup[]
  // reference is the associated PullRequest
  reference: {
    number: number | undefined
    // the commitOid if the comment is associated with a commit
    text?: string | null | undefined
    author:
      | {
          login: string
        }
      | null
      | undefined
  }
  repository: {
    id: string
    isPrivate: boolean
    name: string
    owner: {
      id: string
      login: string
      url: string
    }
  }
  reviewVariantType?: CommentReviewVariantType | null
  state: string
  viewerCanBlockFromOrg: boolean
  viewerCanMinimize: boolean
  viewerCanSeeMinimizeButton: boolean
  viewerCanSeeUnminimizeButton: boolean
  viewerCanReact?: boolean
  viewerCanReport: boolean
  viewerCanReportToMaintainer: boolean
  viewerCanUnblockFromOrg: boolean
  viewerDidAuthor: boolean
  viewerRelationship: string
  subjectType?: string | undefined
  stafftoolsUrl?: string | null
  url: string
  viewerCanDelete: boolean
  viewerCanUpdate: boolean
  ' $fragmentSpreads': FragmentRefs<'ReactionViewerRelayGroups'>
}

export type CommentWithoutFragment = Omit<Comment, ' $fragmentSpreads'>

export type Author = {
  avatarUrl: string
  id: string
  login: string
  url: string
  __typename?: 'Author'
}

export type CommentAuthor = {
  avatarUrl: string
  login: string
  url: string
}

export type UserContentEdit = {
  editor: Partial<Author> | null | undefined
  id?: string
  __typename?: 'UserContentEdit'
}

export type ThreadSummary = {
  id: string
  author: {
    avatarUrl: string
    login: string
  }
  commentCount: number
  commentsConnectionId?: string
  diffSide?: DiffSide | null
  isOutdated: boolean
  line?: number | null
  startLine?: number | null
  startDiffSide?: DiffSide | null
}

export type NavigationThread = {
  id: string
  pathDigest: string
  isResolved: boolean
  firstReviewCommentId: number | undefined | null
  line: number | null | undefined
  path: string
}

export interface MarkerNavigationImplementation {
  /**
   * Navigate to the next marker
   */
  incrementActiveMarker: (currentMarkerId: string) => void
  /**
   * Navigate to the previous marker
   */
  decrementActiveMarker: (currentMarkerId: string) => void
  /**
   * The threads and annotations available for navigation
   */
  filteredMarkers: Array<NavigationThread | DiffAnnotation>
  /**
   * Function to call after global marker navigation has been activated
   */
  onActivateGlobalMarkerNavigation: () => void
  /**
   * Active global marker id
   */
  activeGlobalMarkerID: string | undefined
  /**
   * Optional name of the portal container the overlay will be rendered into. Must be
   * registered with registerPortalRoot or an error will be thrown.
   */
  overlayPortalContainerName?: string
}

export type SuggestedChangesConfiguration = {
  showSuggestChangesButton: boolean
  isValidSuggestionRange: boolean
  sourceContentFromDiffLines: string | undefined
  onInsertSuggestedChange: () => void
  shouldInsertSuggestedChange?: boolean
}

export type ConfigureSuggestedChangesImplementation = {
  selectedDiffRowRange: LineRange | undefined
  configureSuggestedChangesFromLineRange: (
    rowRange?: LineRange,
    shouldInsertSuggestedChange?: boolean,
  ) => SuggestedChangesConfiguration | undefined
  shouldStartNewConversationWithSuggestedChange: boolean | undefined
}

// The subject of the comment
// e.g. PullRequest or a Commit
export type Subject = {
  isInMergeQueue?: boolean
  state?: string
}

export interface ViewerData {
  avatarUrl: string
  diffViewPreference: string
  isSiteAdmin: boolean
  lineSpacingPreference: 'compact' | 'relaxed'
  commentsPreference: CommentsPreference
  login: string
  tabSizePreference: number
  viewerCanComment: boolean
  viewerCanApplySuggestion: boolean
}

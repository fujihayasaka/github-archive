import type {RemoteProvider} from '@github/codespaces-lsp'
import type {DirectoryItem, WebCommitInfo} from '@github-ui/code-view-types'
import type {
  CopilotChatOrg,
  CopilotChatPayload,
  CopilotChatRepo,
} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import type {Repository} from '@github-ui/current-repository'
import type {CurrentUser, RefInfo} from '@github-ui/repos-types'
import type {SafeHTMLString} from '@github-ui/safe-html'
import type {FileStatuses} from '@github-ui/web-commit-dialog'
import type {Hunk, ParsedDiff} from 'diff'

import type {ExtendedDiff, PersistedDiffs, PushableDiffs, SerializedDiffs} from './file-syncer-types'

export interface Label {
  color: string
  name: string
}

export interface PullRequestData {
  id: string
  number: string
  title: string
  headBranch: string
  headSHA: string
  baseBranch: string
  isOpen: boolean
  databaseId?: number
  authorLogin: string
}

interface WorkspaceEditorChatPayload extends CopilotChatPayload {
  ssoOrganizations: CopilotChatOrg[]
  currentTopic: CopilotChatRepo
  apiURL: string
}

export interface WorkspaceEditorRoutePayload {
  blobContents?: string
  snapshotUploadUri?: string
  isBinary?: boolean
  compareBlobContents?: string
  compareRef?: string
  copilotAccessAllowed: boolean
  currentUser?: CurrentUser
  diffPaths?: TaskFileTreeData
  fileStatuses?: FileStatuses
  fileTree: TaskFileTreeData
  fileTreeProcessingTime: number
  findFileWorkerPath: string
  focusedTask?: FocusedTaskData
  foldersToFetch: string[]
  large: boolean
  helpUrl: string
  path: string
  pullRequestNumber: string
  pullRequest: PullRequestData
  refInfo: RefInfo
  repo: Repository
  webCommitInfo: WebCommitInfo
  copilot: WorkspaceEditorChatPayload
  showOverview?: boolean
  editorSettings: EditorSettings
  treeExpanded?: boolean
  showDiff?: boolean
  isNewFilePage: boolean
}

export type MonacoWorkerUrls = {
  editor: string
  css: string
  html: string
  json: string
  ts: string
}

export interface WorkspaceEditorAppPayload extends CopilotChatPayload {
  markdownDocsUrl: string
  monacoWorkerUrls: MonacoWorkerUrls
}

/**
 * Route Payload used by the CurrentPullRequestProvider to get the pull request
 * data. Components that require the pull request should use
 * `useCurrentPullRequest` instead of `useRoutePayload` so it is updated as
 * commits are made or recieved.
 */
export interface WorkspaceEditorPullRequestPayload {
  pullRequest: PullRequestData
}

export type EditorSettings = {
  codeLineWrapEnabled: boolean
  whitespaceHidden: boolean
  problemsHidden: boolean
}

export const TaskTypes = {
  Autofix: 'autofix',
  Suggestion: 'suggestion',
  Generative: 'generative',
} as const

export type TaskTypes = (typeof TaskTypes)[keyof typeof TaskTypes]

/**
 * Basic data required for rendering a task in the task list or in the editor.
 */
export interface DisplayTaskData {
  author?: Author
  lineNumber?: number
  outdated: boolean
  path: string
  sourceId: number
  startLineNumber?: number
  type: TaskTypes
}

export type SuggestionCommentData = Record<number, DisplayTaskData>

export interface FocusedTaskData extends DisplayTaskData {
  html: SafeHTMLString
  suggestions: FocusedTaskSuggestion[]
  previousComments: FocusedTaskContextComment[]
  followingComments: FocusedTaskContextComment[]
}

type FocusedTaskContextComment = {
  author?: Author
  html: SafeHTMLString
  id: number
}

export interface FocusedSuggestionTaskData extends FocusedTaskData {
  type: typeof TaskTypes.Suggestion
}

export interface Author {
  displayLogin: string
  avatarUrl: string
}

export interface FocusedTaskSuggestion {
  filePath: string
  // Some sources already have a raw diff string so allow that
  diff: string | FocusedSuggestionHunk
  eofContent?: string
}

// Subset of ParsedDiff's Hunk we need to apply suggestion
export interface FocusedSuggestionHunk
  extends Pick<Hunk, 'oldStart' | 'oldLines' | 'newStart' | 'newLines' | 'lines'> {}

export interface FocusedGenerativeTaskData extends FocusedTaskData {
  comment: ThreadComment
  replies: ThreadComment[]
  type: typeof TaskTypes.Generative
}

export interface ThreadComment {
  author?: Author
  body: string
  bodyText: string
  commitOid: string
  createdAt: string
  updatedAt: string
  diffHunk: string
  id: number
  inReplyToId?: number
  lineNumber?: number
  originalCommitOid: string
  originalLineNumber: number
  originalStartLineNumber: number
  path: string
  pullRequestId: number
  side: string
  startLineNumber?: number
  startSide: string
  subjectType: string
  type: typeof TaskTypes.Generative
}

export interface ITunnelProperties {
  tunnelId: string
  clusterId: string
  domain: string
  connectAccessToken: string
  managePortsAccessToken: string
  serviceUri: string
}

export interface CodespaceInfoBase {
  cloud_environment: {
    guid: string
  }
  environment_data: {
    state: CodespaceStateInfo
    connection: {
      sessionPath?: string
      tunnelProperties?: ITunnelProperties
    }
    friendlyName: string
    skuDisplayName: string
    skuName: string
    location: string
    features: Record<string, string>
    devcontainer_path?: string
  }
}

export const CodespaceStateInfo = {
  Provisioning: 'Provisioning',
  Deleted: 'Deleted',
  Available: 'Available',
  Unavailable: 'Unavailable',
  Shutdown: 'Shutdown',
  ShuttingDown: 'ShuttingDown',
  Failed: 'Failed',
  Starting: 'Starting',
  Exporting: 'Exporting',
  Queued: 'Queued',
  Updating: 'Updating',
  Rebuilding: 'Rebuilding',
} as const

export type CodespaceStateInfo = (typeof CodespaceStateInfo)[keyof typeof CodespaceStateInfo]

export type CodespaceErrorResponse = {
  error: string
}

export interface CodespaceInfoExtended {
  data: CodespaceInfoBase
  isReconnect: boolean
}

// Well-known Codespace states.
const codespaceInitialStates = ['none', 'creating', 'starting'] as const
export type TCodespaceInitialState = (typeof codespaceInitialStates)[number]
export type TCodespaceState = TCodespaceInitialState | 'ready' | 'failed'

export const isCodespaceInitialState = (codespaceState: TCodespaceState) => {
  return codespaceInitialStates.some(initialState => initialState === codespaceState)
}

export interface ConnectedCodespaceData {
  codespaceInfo: CodespaceInfoBase | null
  codespaceState: TCodespaceState
  workspaceRoot: string
  isRecoveryContainer: boolean
  permissionsStatus?: PermissionsStatus
  creationErrorMessage?: string
  remoteProvider?: RemoteProvider
  recreateCodespace: (() => void) | (() => Promise<void>)
  pollForPermissionsAccepted: () => void
}

export interface PermissionsStatus {
  accepted: boolean
  allowPermissionsUrl?: string
}

export interface TerminalTasks {
  build?: string
  test?: string
  run?: string
}

export interface PortForwarder {
  dataScraper: (data: string) => void
  forwardedUrl: string
}

export interface OverviewPayload {
  bodyHtml: string
  labels: Label[]
  titleHtml: string
}

export type BlobPayload = {
  blobContents?: string
  commitOid: string
  languageName?: string
  languageId?: string
  path: string
  refName: string
}

export type FileData = {
  oldFilePath: string
  newFilePath: string
  oldContents: string
  newContents: string
}

export type FileDataWithStatus = FileData & {status: 'A' | 'D' | 'M' | 'R' | undefined}

export interface FileDataStore {
  addFile: (path: string) => void
  applyAllTaskSuggestionsToContent: (
    task: FocusedTaskData,
    originals: BlobPayload[],
  ) => {[filePath: string]: string | undefined}
  applyFileToContent: (
    suggestions: Array<{filePath: string; diff: Hunk; eofContent?: string}>,
    originals: Array<{path: string; blobContents: string}>,
  ) => {[filePath: string]: string | undefined}
  applySuggestionsToContent: (
    suggestions: FocusedTaskSuggestion[],
    originals: BlobPayload[],
    task?: FocusedTaskData,
  ) => {[filePath: string]: string | undefined}
  deleteFile: (path: string, originalContent: string | undefined) => void
  editFile: (args: {filePath: string; originalContent?: string; newFilePath?: string; newFileContent?: string}) => void
  getChangedFiles: () => ChangedFile[]
  getCurrentFileContent: (
    path: string,
    originalContent: string | undefined,
  ) => {content: string | undefined; patch: ExtendedDiff | ParsedDiff | undefined; patchIncluded: boolean}
  getFileStatuses: () => FileStatuses
  getFileTreeData: (mode: FileFilter) => TaskFileTreeData | undefined
  markFilesCommitted: (paths: Iterable<string>) => void
  renameFile(args: {oldFilePath: string; newFilePath: string; originalContent: string | undefined}): void
  resetFile: (filePath: string) => void
  resetFiles: () => void
  storeDiffs: (pushableDiffs: PushableDiffs) => Promise<PersistedDiffs>
  retrieveDiffs: (versionStamp?: number) => SerializedDiffs
}

export const FileFilter = {
  All: 'All files in this repository',
  PR: 'Files in this pull request',
} as const

export type FileFilter = (typeof FileFilter)[keyof typeof FileFilter]

export interface ChangedFile {
  patch: ParsedDiff
  path: string
  status: 'A' | 'D' | 'M' | 'R' | undefined
}

export type DiffStyle = 'split' | 'inline'

export interface TaskDirectoryItem extends DirectoryItem {}

export type TaskFileTreeData = Record<string, {items: TaskDirectoryItem[]; totalCount: number}>

export const BannerType = {
  COMPUTE_LIMIT: 'compute-limit',
  COPILOT_BILLING: 'copilot-billing',
  IDLE_SPARK: 'idle-spark',
  MULTIPLE_SPARKS: 'multiple-sparks',
  RUNTIME_LIMIT: 'runtime-limit',
  SPARK_INFRA_LIMIT: 'spark-infra-limit',
  COMMIT_SUCCESS: 'commit-success',
  CONNECTION_ERROR: 'connection-error',
  COPILOT_CHAT_QUOTA: 'copilot-chat-quota',
  CONNECTION_RELOAD: 'connection-reload',
  PREVIEW_AUTH_FAILED: 'preview-auth-failed',
} as const
export type BannerType = (typeof BannerType)[keyof typeof BannerType] | undefined

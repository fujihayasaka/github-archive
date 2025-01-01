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
}

interface WorkspaceEditorChatPayload extends CopilotChatPayload {
  ssoOrganizations: CopilotChatOrg[]
  currentTopic: CopilotChatRepo
  apiURL: string
}

export interface WorkspaceEditorRoutePayload {
  blobContents?: string
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
  helpUrl: string
  path: string
  pullRequestNumber: string
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
}

export enum TaskTypes {
  Autofix = 'autofix',
  Suggestion = 'suggestion',
  Generative = 'generative',
}

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
  type: TaskTypes.Suggestion
}

export interface Author {
  displayLogin: string
  avatarUrl: string
}

export interface FocusedTaskSuggestion {
  filePath: string
  // Some sources already have a raw diff string so allow that
  diff: string | FocusedSuggestionHunk
}

// Subset of ParsedDiff's Hunk we need to apply suggestion
export interface FocusedSuggestionHunk
  extends Pick<Hunk, 'oldStart' | 'oldLines' | 'newStart' | 'newLines' | 'lines'> {}

export interface FocusedGenerativeTaskData extends FocusedTaskData {
  comment: ThreadComment
  replies: ThreadComment[]
  type: TaskTypes.Generative
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
  type: TaskTypes.Generative
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

export enum CodespaceStateInfo {
  Provisioning = 'Provisioning',
  Deleted = 'Deleted',
  Available = 'Available',
  Unavailable = 'Unavailable',
  Shutdown = 'Shutdown',
  ShuttingDown = 'ShuttingDown',
  Failed = 'Failed',
  Starting = 'Starting',
  Exporting = 'Exporting',
  Queued = 'Queued',
  Updating = 'Updating',
  Rebuilding = 'Rebuilding',
}

export type CodespaceErrorResponse = {
  error: string
}

export interface CodespaceInfoExtended {
  data: CodespaceInfoBase
  isReconnect: boolean
}

// Well-known Codespace states.
export type TCodespaceState = 'none' | 'creating' | 'starting' | 'ready' | 'failed'

export interface ConnectedCodespaceData {
  codespaceInfo: CodespaceInfoBase | null
  codespaceState: TCodespaceState
  workspaceRoot: string
  isRecoveryContainer: boolean
  permissionsStatus?: PermissionsStatus
  creationErrorMessage?: string
  remoteProvider?: RemoteProvider
  recreateCodespace: () => void
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
  applySuggestionsToContent: (
    task: FocusedTaskData,
    suggestions: FocusedTaskSuggestion[],
    originals: BlobPayload[],
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
  retrieveDiffs: () => SerializedDiffs
}

export enum FileFilter {
  All = 'All files in this repository',
  PR = 'Files in this pull request',
}

export interface ChangedFile {
  patch: ParsedDiff
  path: string
  status: 'A' | 'D' | 'M' | 'R' | undefined
}

export type DiffStyle = 'split' | 'inline'

export interface TaskDirectoryItem extends DirectoryItem {}

export type TaskFileTreeData = Record<string, {items: TaskDirectoryItem[]; totalCount: number}>

export type BannerType = 'commit-success' | undefined

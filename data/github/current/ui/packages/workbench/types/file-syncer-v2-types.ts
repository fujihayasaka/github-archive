import type {ParsedDiff} from 'diff'
/**
 * RPC methods that run on the compute
 */
export type ServerRpcMethods = {
  openFile(path: string): Promise<void>
  createDirectory(params: {path: string}): void
  deleteFile(params: {path: string}): void
  renameFile(params: {oldPath: string; newPath: string}): void
  writeFileString(params: {path: string; content: string}): void
  writeFileBytes(params: {path: string; content: Uint8Array}): void
  writeFileDiff(params: {path: string; diff: ParsedDiff}): void
  readFileString(params: {path: string}): string
  readFileBytes(params: {path: string}): Uint8Array
  readFileDiff(params: {path: string}): ParsedDiff
  pauseFileWatchers(): void
  resumeFileWatchers(): void
  getDirectoryContents(params: {path: string}): FileEntry[]
  createCommit(params: {message: string}): {sha: string}
  checkoutCommitish(params: {sha: string}): string
  getGitStatus(): Promise<GitFileStatuses>
}

export type FileEntry = {
  type: 'file' | 'directory'
  path: string
}

export type FileChange = {
  type: 'file' | 'directory'
  path: string
  changeType: 'added' | 'modified' | 'deleted' | 'renamed'
  oldPath?: string
}

export type GitFileStatuses = Record<string, GitFileStatus>
export type GitFileStatus = {
  fileName: string
  editType: 'create' | 'update' | 'delete' | 'rename'
}

export type ClientRpcMethods = {
  notifyFileChanged(params: {changes: FileChange[]}): void
}

export interface IDisposable {
  isDisposed?: boolean
  dispose(): void
}

export interface IFileSyncer extends IDisposable {
  openFile(path: string): Promise<void>
  createDirectory(path: string): Promise<void>
  deleteFile(path: string): Promise<void>
  renameFile(oldPath: string, newPath: string): Promise<void>
  writeFileString(path: string, content: string): Promise<void>
  writeFileBytes(path: string, content: Uint8Array): Promise<void>
  writeFileDiff(path: string, diff: ParsedDiff): Promise<void>
  readFileString(path: string): Promise<string>
  readFileBytes(path: string): Promise<Uint8Array>
  readFileDiff(path: string): Promise<ParsedDiff>
  getDirectoryContents(path: string): Promise<FileEntry[]>
  pauseFileWatchers(): Promise<void>
  resumeFileWatchers(): Promise<void>
  createCommit(message: string, sasUri?: string): Promise<{sha: string}>
  checkoutCommitish(sha: string): Promise<string>
  getGitStatus(): Promise<GitFileStatuses>
}

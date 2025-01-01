import type {FileStatus} from '@github-ui/web-commit-dialog'
import type {ParsedDiff} from 'diff'

export type RpcMethods = {
  pushDiffs(params: {sessionId: string; pushableDiffs: PushableDiffs}): number
  getDiffs(params: {sessionId: string}): SerializedDiffs
  reportStatus(params: {status: FileSyncerStatus}): void
  getTimestamp(): number
}

export interface IFileSyncerBridge {
  pushDiffs(sessionId: string, pushableDiffs: PushableDiffs): Promise<number>
  getDiffs(sessionId: string): Promise<SerializedDiffs>
  reportStatus(status: FileSyncerStatus): Promise<void>
  getTimestamp(): Promise<number>
}

export type DiffEntry = {
  path: string
  /**
   * This is the current file status of the file in the local storage,
   * based on the operation performed by the user or a command inside the codespace.
   * It could be 'A', 'M', or 'D'
   */
  currentFileStatus: FileStatus | undefined
  /**
   * This is the original file status that was present when the diff was created.
   * It will be 'A' for the newly added files
   */
  originalFileStatus: FileStatus | undefined
  diff: ExtendedDiff
}

/**
 * Patches/diffs persisted in local storage
 */
export type PersistedDiffs = {
  sessionId: string
  latestTimestamp: number
  diffs: DiffEntry[]
}

/**
 * Copilot Workspace FileSyncer Types
 * */

export type ExtendedDiff = ParsedDiff & {
  /**
   * True if the file was deleted, false otherwise.
   */
  isDeleted: boolean

  /**
   * This is an optional property that can be used to signal why this diff belongs to a file that is ignored.
   * It seems strange to have this property considering that why would we even produce diffs for files that are ignored.
   * However, given that diffs only ever grow in a session (we never retract them but only overwrite them) and that
   * we want to surface ignorance in the web client, we need to somehow attach such semantic information to diffs.
   */
  ignoreReason: 'ignored-by-git' | 'base-file-too-big' | 'diff-too-big' | null
}

export type SerializedDiffs = {
  sessionId: string
  latestTimestamp: number
  diffs: Array<{
    path: string
    diff: string
  }>
}

export type PathWithExtendedDiff = {
  path: string
  diff: ExtendedDiff
}

export type PushableDiffs = {
  isAdditive: boolean
  diffs: Array<{
    path: string
    diff: string
  }>
}

export type FileSyncerStatus = {
  codespaceName: string
  status: 'operational' | 'erroneous' | 'unknown'
  failureKinds: string[]
}

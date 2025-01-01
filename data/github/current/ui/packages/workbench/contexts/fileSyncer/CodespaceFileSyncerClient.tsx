import type {ParsedDiff} from 'diff'
import type {TypedJSONRPCClient} from 'json-rpc-2.0'

import type {FileEntry, GitFileStatuses, IFileSyncer, ServerRpcMethods} from '../../types/file-syncer-v2-types'

export const RPC_TIMEOUT = 5000

export class CodespaceFileSyncerClient implements IFileSyncer {
  isDisposed = false
  private jsonRpcClient: TypedJSONRPCClient<ServerRpcMethods>

  constructor(jsonRpcClient: TypedJSONRPCClient<ServerRpcMethods>) {
    this.jsonRpcClient = jsonRpcClient
  }

  async openFile(path: string): Promise<void> {
    if (this.isDisposed) throw new Error('FileSyncer is disposed')
    return await this.jsonRpcClient.timeout(RPC_TIMEOUT).request('openFile', {path})
  }

  async createDirectory(path: string): Promise<void> {
    if (this.isDisposed) throw new Error('FileSyncer is disposed')
    return await this.jsonRpcClient.timeout(RPC_TIMEOUT).request('createDirectory', {path})
  }

  async deleteFile(path: string): Promise<void> {
    if (this.isDisposed) throw new Error('FileSyncer is disposed')
    return await this.jsonRpcClient.timeout(RPC_TIMEOUT).request('deleteFile', {path})
  }

  async renameFile(oldPath: string, newPath: string): Promise<void> {
    if (this.isDisposed) throw new Error('FileSyncer is disposed')
    return await this.jsonRpcClient.timeout(RPC_TIMEOUT).request('renameFile', {oldPath, newPath})
  }

  async writeFileString(path: string, content: string): Promise<void> {
    if (this.isDisposed) throw new Error('FileSyncer is disposed')
    return await this.jsonRpcClient.timeout(RPC_TIMEOUT).request('writeFileString', {path, content})
  }

  async writeFileBytes(path: string, content: Uint8Array): Promise<void> {
    if (this.isDisposed) throw new Error('FileSyncer is disposed')
    return await this.jsonRpcClient.timeout(RPC_TIMEOUT).request('writeFileBytes', {path, content})
  }

  async writeFileDiff(path: string, diff: ParsedDiff): Promise<void> {
    if (this.isDisposed) throw new Error('FileSyncer is disposed')
    return await this.jsonRpcClient.timeout(RPC_TIMEOUT).request('writeFileDiff', {path, diff})
  }

  async readFileString(path: string): Promise<string> {
    if (this.isDisposed) throw new Error('FileSyncer is disposed')
    return await this.jsonRpcClient.timeout(RPC_TIMEOUT).request('readFileString', {path})
  }

  async readFileBytes(path: string): Promise<Uint8Array> {
    if (this.isDisposed) throw new Error('FileSyncer is disposed')
    return await this.jsonRpcClient.timeout(RPC_TIMEOUT).request('readFileBytes', {path})
  }

  async readFileDiff(path: string): Promise<ParsedDiff> {
    if (this.isDisposed) throw new Error('FileSyncer is disposed')
    return await this.jsonRpcClient.timeout(RPC_TIMEOUT).request('readFileDiff', {path})
  }

  async getDirectoryContents(path: string): Promise<FileEntry[]> {
    if (this.isDisposed) throw new Error('FileSyncer is disposed')
    return await this.jsonRpcClient.timeout(RPC_TIMEOUT).request('getDirectoryContents', {path})
  }

  async pauseFileWatchers(): Promise<void> {
    if (this.isDisposed) throw new Error('FileSyncer is disposed')
    return await this.jsonRpcClient.timeout(RPC_TIMEOUT).request('pauseFileWatchers', {})
  }

  async resumeFileWatchers(): Promise<void> {
    if (this.isDisposed) throw new Error('FileSyncer is disposed')
    return await this.jsonRpcClient.timeout(RPC_TIMEOUT).request('resumeFileWatchers', {})
  }

  async createCommit(message: string, sasUri: string): Promise<{sha: string}> {
    if (this.isDisposed) throw new Error('FileSyncer is disposed')
    return await this.jsonRpcClient.timeout(RPC_TIMEOUT).request('createCommit', {message, sasUri})
  }

  async checkoutCommitish(sha: string): Promise<string> {
    if (this.isDisposed) throw new Error('FileSyncer is disposed')
    return await this.jsonRpcClient.timeout(RPC_TIMEOUT).request('checkoutCommitish', {sha})
  }

  async getGitStatus(): Promise<GitFileStatuses> {
    if (this.isDisposed) throw new Error('FileSyncer is disposed')
    return await this.jsonRpcClient.timeout(RPC_TIMEOUT).request('getGitStatus', {})
  }

  dispose(): void {
    // Clean up resources
    this.isDisposed = true
  }
}

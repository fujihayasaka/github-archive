import {ContainerClient} from '@azure/storage-blob'
import type {ParsedDiff} from 'diff'

import type {FileEntry, GitFileStatuses, IFileSyncer} from '../../types/file-syncer-v2-types'

async function blobToString(blob: Blob): Promise<string> {
  const fileReader = new FileReader()
  return new Promise((resolve, reject) => {
    fileReader.onloadend = ev => {
      resolve(ev.target?.result as string)
    }
    fileReader.onerror = reject
    fileReader.readAsText(blob)
  })
}

export class AzureBlobFileSyncerClient implements IFileSyncer {
  private containerClient: ContainerClient

  constructor(storageUrl: string) {
    this.containerClient = new ContainerClient(storageUrl)
  }

  async hasContent(): Promise<boolean> {
    try {
      // Check if there's at least one file in the container
      for await (const _ of this.containerClient.listBlobsFlat()) {
        return true
      }

      return false
    } catch {
      return false
    }
  }

  /**
   * Normalizes a file path for use with Azure Blob Storage
   */
  private normalizePath(path: string): string {
    let normalizedPath = path.startsWith('/') ? path.substring(1) : path
    if (!normalizedPath.startsWith('spark-template/')) {
      normalizedPath = `spark-template/${normalizedPath}`
    }
    return normalizedPath
  }

  /**
   * Denormalizes a blob path for client use
   */
  private denormalizePath(blobPath: string): string {
    return blobPath.replace(/^spark-template\//, '')
  }

  async openFile(path: string): Promise<void> {
    const blobPath = this.normalizePath(path)
    const blobClient = this.containerClient.getBlobClient(blobPath)
    const exists = await blobClient.exists()

    if (!exists) {
      throw new Error(`File not found: ${path}`)
    }
  }

  async createDirectory(_path: string): Promise<void> {
    // NOOP
  }

  async deleteFile(_path: string): Promise<void> {
    // NOOP
  }

  async renameFile(_oldPath: string, _newPath: string): Promise<void> {
    // NOOP
  }

  async writeFileString(_path: string, _content: string, _modifiedOutsideEditor?: boolean): Promise<void> {
    // NOOP
  }

  async writeFileBytes(_path: string, _content: Uint8Array): Promise<void> {
    // NOOP
  }

  async writeFileDiff(_path: string, _diff: ParsedDiff): Promise<void> {
    // NOOP
  }

  async readFileString(path: string): Promise<string> {
    const blobPath = this.normalizePath(path)
    const blobClient = this.containerClient.getBlobClient(blobPath)

    const downloadResponse = await blobClient.download(0)
    const downloaded = await blobToString(await downloadResponse.blobBody!)

    return downloaded
  }

  async readFileBytes(path: string): Promise<Uint8Array> {
    const blobString = await this.readFileString(path)
    const encoder = new TextEncoder()
    const encoded = encoder.encode(blobString)
    return encoded
  }

  async readFileDiff(path: string): Promise<ParsedDiff> {
    return {
      hunks: [],
      oldFileName: path,
      newFileName: path,
    }
  }

  async getDirectoryContents(_path: string): Promise<FileEntry[]> {
    const entries: FileEntry[] = []

    for await (const blob of this.containerClient.listBlobsFlat()) {
      const entryPath = this.denormalizePath(blob.name)

      const entry: FileEntry = {
        path: entryPath,
        type: 'file',
      }

      entries.push(entry)
    }

    return entries
  }

  async pauseFileWatchers(): Promise<void> {
    // NOOP
  }

  async resumeFileWatchers(): Promise<void> {
    // NOOP
  }

  async createCommit(_message: string, _sasUri: string): Promise<{sha: string}> {
    // NOOP
    return {sha: ''}
  }

  async checkoutCommitish(_commitish: string): Promise<string> {
    // NOOP
    return ''
  }

  async getGitStatus(): Promise<GitFileStatuses> {
    // NOOP
    return {}
  }

  dispose(): void {
    // NOOP
  }
}

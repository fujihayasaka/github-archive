import type {PatchStatus} from '@github-ui/diff-file-helpers'

import {NO_FILE_EXTENSION} from './FileFilter'

export type SummaryDelta = {
  path: string
  pathDigest: string
}

export type AnnotationLevels = 'NOTICE' | 'WARNING' | 'FAILURE'

export type DiffDelta = SummaryDelta & {
  changeType: PatchStatus
  totalCommentsCount?: number
  highestAnnotationLevel?: AnnotationLevels
}

/**
 * Compare two strings with case-first ordering. ZZZ.txt will come before aaa.txt with this strategy.
 */
export function caseFirstCompare(a: string, b: string): number {
  if (a < b) return -1
  if (a > b) return 1
  return 0
}

function compareDirectoryNames<T extends SummaryDelta>(a: DirectoryNode<T>, b: DirectoryNode<T>) {
  return caseFirstCompare(a.name, b.name)
}

function compareFileNames<T extends SummaryDelta>(a: FileNode<T>, b: FileNode<T>) {
  return caseFirstCompare(a.fileName!, b.fileName!)
}

function getFileDiff<T extends SummaryDelta>(file: FileNode<T>) {
  return file.diff
}

export class FileNode<T extends SummaryDelta> {
  declare diff: T
  declare filePath: string
  declare fileName: string | undefined
  declare directoryParts: string[]

  constructor(diff: T) {
    this.diff = diff
    this.filePath = diff.path
    const pathParts = this.filePath.split('/')
    this.fileName = pathParts[pathParts.length - 1]
    this.directoryParts = pathParts.slice(0, pathParts.length - 1)
  }
}

export class DirectoryNode<T extends SummaryDelta> {
  directories: Array<DirectoryNode<T>> = []
  files: Array<FileNode<T>> = []

  #directoriesByName = new Map<string, DirectoryNode<T>>()

  declare name: string
  declare path: string

  constructor(name: string, path: string) {
    this.name = name
    this.path = path
  }

  getOrCreateDirectory(name: string) {
    let directory = this.#directoriesByName.get(name)

    if (!directory) {
      const pathPrefix = this.path ? `${this.path}/` : ''
      directory = new DirectoryNode(name, `${pathPrefix}${name}`)
      this.directories.push(directory)
      this.#directoriesByName.set(name, directory)
    }

    return directory
  }

  sort() {
    this.directories.sort(compareDirectoryNames)
    this.files.sort(compareFileNames)

    for (const subDirectory of this.directories) {
      subDirectory.sort()
    }
  }

  getOrderedDiffs() {
    const diffs = this.files.map(getFileDiff)

    for (const subDirectory of this.directories) {
      diffs.push(...subDirectory.getOrderedDiffs())
    }

    return diffs
  }
}

export function getFileTree<T extends SummaryDelta>(summaryDeltas: readonly T[]): DirectoryNode<T> {
  const baseNode = new DirectoryNode<T>('', '')
  const files = summaryDeltas.map(diff => new FileNode<T>(diff))

  for (const file of files) {
    let directory = baseNode
    for (const directoryPath of file.directoryParts) {
      directory = directory.getOrCreateDirectory(directoryPath)
    }
    directory.files.push(file)
  }

  baseNode.sort()
  return baseNode
}

export function sortDiffEntries<T extends SummaryDelta>(patches: Array<T | null | undefined>): T[] {
  const filteredPatches = patches.filter((patch): patch is T => !!patch)
  const fileTree = getFileTree(filteredPatches)
  return fileTree.getOrderedDiffs()
}

type FileProps = string | undefined | {newPath?: string | null | undefined; oldPath?: string | null | undefined}

export function getFileExtension(file: FileProps): string {
  let path: string | null | undefined
  if (typeof file === 'string') {
    path = file
  } else {
    path = file?.newPath || file?.oldPath
  }
  const lastPeriodIndex = path?.lastIndexOf('.')
  if (!path) {
    return ''
  }
  if (!lastPeriodIndex || lastPeriodIndex < 0) {
    return NO_FILE_EXTENSION as string
  }

  return `.${path.substring(lastPeriodIndex + 1)}`
}

export function getFileExtensionCounts(
  diffs: Readonly<Array<{path: string}>> | Array<{path: string}>,
): Record<string, number> {
  const fileExtensionCounts: Record<string, number> = {}
  diffs.map(diff => {
    const fileExtension = getFileExtension(diff.path)
    if (fileExtensionCounts[fileExtension] !== undefined) {
      fileExtensionCounts[fileExtension] += 1
    } else {
      fileExtensionCounts[fileExtension] = 1
    }
  })

  return fileExtensionCounts
}

import {type ParsedDiff, structuredPatch} from 'diff'

import type {DiffEntry} from './file-syncer-types'
import type {FileData, FileDataWithStatus} from './workspace-editor-types'

export function formatPatches(fileData: FileData[]) {
  const patchesToWrite = fileData.map(({oldFilePath, oldContents, newFilePath, newContents}) => {
    const patch = structuredPatch(oldFilePath, newFilePath, oldContents, newContents)

    // this is to work around a bug in jsdiff itself - see https://github.com/kpdecker/jsdiff/issues/228
    for (const diff of patch.hunks) {
      diff.linedelimiters = Array(diff.lines.length).fill('\n')
    }

    return patch
  })

  const newPatches: Record<string, ParsedDiff> = {}
  for (const patchToWrite of patchesToWrite) {
    const path = patchToWrite.newFileName || patchToWrite.oldFileName || ''
    newPatches[path] = patchToWrite
  }
  return newPatches
}

export function createDiffEntries(fileData: FileDataWithStatus[]) {
  return fileData.map(({oldFilePath, oldContents, newFilePath, newContents, status}) => {
    const diffEntry: DiffEntry = {
      path: newFilePath || oldFilePath || '',
      currentFileStatus: status,
      originalFileStatus: status,
      diff: {
        ...structuredPatch(oldFilePath, newFilePath, oldContents, newContents),
        isDeleted: status === 'D',
        ignoreReason: null,
      },
    }

    // this is to work around a bug in jsdiff itself - see https://github.com/kpdecker/jsdiff/issues/228
    for (const diff of diffEntry.diff.hunks) {
      diff.linedelimiters = Array(diff.lines.length).fill('\n')
    }

    return diffEntry
  })
}

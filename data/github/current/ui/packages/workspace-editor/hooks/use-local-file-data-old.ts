import {useCurrentRepository} from '@github-ui/current-repository'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {clearLocalStorage, useLocalStorage} from '@github-ui/use-safe-storage/local-storage'
import type {FileStatuses} from '@github-ui/web-commit-dialog'
import {applyPatch, type ParsedDiff} from 'diff'
import {useCallback, useRef, useState} from 'react'

import {isAdded} from '../utilities/file-status-helpers'
import type {PushableDiffs} from '../utilities/file-syncer-types'
import {formatPatches} from '../utilities/patch-helpers'
import {applySuggestions, problemWithTaskSuggestions} from '../utilities/suggestion-helpers'
import {addPathToTree} from '../utilities/tree-helpers'
import {
  type BlobPayload,
  type FileData,
  type FileDataStore,
  FileFilter,
  type FocusedTaskData,
  type FocusedTaskSuggestion,
  type WorkspaceEditorRoutePayload,
} from '../utilities/workspace-editor-types'
import {useLocalSuggestionState} from './use-local-suggestion-state'

/**
 * Returns a stable callback that will not change between renders but always calls the latest version of the function.
 * This is useful when we don't want changes in a function to trigger re-renders in consumers.
 */
const useStableCallback = <A extends unknown[], R>(fn: (...args: A) => R): ((...args: A) => R) => {
  const trackingRef = useRef<(...args: A) => R>(fn)
  // eslint-disable-next-line react-compiler/react-compiler
  trackingRef.current = fn

  return useCallback((...args: A) => trackingRef.current(...args), [])
}

function areFileStatusesEqual(a: FileStatuses, b: FileStatuses): boolean {
  if (Object.keys(a).length !== Object.keys(b).length) return false
  for (const key of Object.keys(a)) {
    if (a[key] !== b[key]) return false
  }

  return true
}

function getFileStatusesFromPatches(patches: {[filePath: string]: ParsedDiff}): FileStatuses {
  return Object.keys(patches).reduce((result, path) => {
    const patch = patches[path]

    if (!patch || (!patch.oldFileName && !patch.newFileName)) return result

    if (!patch.oldFileName && patch.newFileName) {
      result[patch.newFileName] = 'A'
    } else if (patch.oldFileName && !patch.newFileName) {
      result[patch.oldFileName] = 'D'
    } else if (patch.oldFileName !== patch.newFileName) {
      result[patch.oldFileName!] = 'R'
    } else if (patch.oldFileName === patch.newFileName) {
      result[path] = 'M'
    }

    return result
  }, {} as FileStatuses)
}

function buildPatchesStorageKey(org: string, repoName: string, entityId: string) {
  return `hadron-editor-file-deltas/${org}/${repoName}/${entityId}`
}

/**
 * Use browser local storage state to manage file data. Returned functions remain stable through edits except for the
 * `getFileStatuses` function. We don't want to trigger updates to consumers every time the file content changes.
 * Monaco handles updating the editor content for us and we don't want to re-render
 * every consumer of this data every time a character is entered.
 *
 * @returns FileDataStore implementation that uses browser local storage to manage file data
 */
export function useLocalFileData(): FileDataStore {
  const {diffPaths, fileTree, pullRequestNumber} = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {name, ownerLogin} = useCurrentRepository()
  const [patches, setPatches] = useLocalStorage<{[filePath: string]: ParsedDiff}>(
    buildPatchesStorageKey(ownerLogin, name, pullRequestNumber),
    {},
  )
  const [fileStatuses, setFileStatuses] = useState<FileStatuses>(() => getFileStatusesFromPatches(patches))

  const {getAppliedSuggestions, resetSuggestionState, updateAppliedSuggestions} = useLocalSuggestionState()

  const updatePatchesAndStatuses = useStableCallback((newPatches: {[filePath: string]: ParsedDiff}) => {
    setPatches(newPatches)
    setFileStatuses(prevFileStatuses => {
      const newFileStatuses = getFileStatusesFromPatches(newPatches)
      if (!areFileStatusesEqual(prevFileStatuses, newFileStatuses)) {
        return newFileStatuses
      }

      return prevFileStatuses
    })
  })

  const mergePatchesToStored = useStableCallback((fileData: FileData[]) => {
    const newPatches = formatPatches(fileData)
    return Object.assign({...patches}, newPatches)
  })

  const applyAllTaskSuggestionsToContent = useStableCallback(
    (task: FocusedTaskData, originals: BlobPayload[]): {[filePath: string]: string | undefined} => {
      const appliedSuggestions = getAppliedSuggestions()

      // We don't bother pre-checking for conflicts when applying because we'll get the errors anyways
      const problem = problemWithTaskSuggestions(appliedSuggestions, fileStatuses, task, undefined)
      if (problem) {
        alert(problem)
        return {}
      }

      return applySuggestionsToContent(task, task.suggestions, originals)
    },
  )

  // This may be used for cherry-picking individual suggestions so don't merge with above
  const applySuggestionsToContent = useStableCallback(
    (
      task: FocusedTaskData,
      suggestions: FocusedTaskSuggestion[],
      originals: BlobPayload[],
    ): {[filePath: string]: string | undefined} => {
      // Tally up all the diffs we want for the current suggestion
      let newPatches = {...patches}
      const updatedContents: {[filePath: string]: string | undefined} = {}
      for (const {path: filePath, blobContents: originalContent} of originals) {
        const {content: currentContent} = getCurrentFileContent(filePath, originalContent)
        const contents = applySuggestions(filePath, currentContent, suggestions)
        updatedContents[filePath] = contents

        const nextPatch = formatPatches([
          {
            oldFilePath: filePath,
            oldContents: originalContent!,
            newFilePath: filePath,
            newContents: contents!,
          },
        ])
        newPatches = Object.assign(newPatches, nextPatch)
      }

      updatePatchesAndStatuses(newPatches)
      updateAppliedSuggestions(task, suggestions)

      return updatedContents
    },
  )

  /**
   * Returns the contents of the file as the editor should currently have -- i.e.
   * the original blob from server + any diffs that have been generated locally.
   *
   * It doesn't rely on the blobContents from the current route because that's tied
   * to the currently viewed file, and we want to use this with other files when
   * applying suggestions.
   */
  const getCurrentFileContent = useStableCallback((filePath: string, originalContent: string | undefined) => {
    const patch = patches[filePath]
    const result = {
      content: originalContent,
      patchIncluded: false,
      patch,
    }

    if (!patch) {
      return result
    }

    const patchResult = applyPatch(originalContent ?? '', patch)

    // applyPatch returns false if the patch could not be applied so we only compare to false,
    // because we don't want empty string to be to be considered a failure
    if (patchResult === false) {
      return result
    }

    result['content'] = patchResult
    result['patchIncluded'] = true
    return result
  })

  const getChangedFiles = useStableCallback(() => {
    const changedFiles = Object.keys(fileStatuses).map(path => {
      return {
        path,
        status: fileStatuses[path]!,
        patch: patches[path]!,
      }
    })
    return changedFiles
  })

  const getFileStatuses = useCallback(() => {
    return fileStatuses
  }, [fileStatuses])

  const getFileTreeData = useCallback(
    (mode: FileFilter) => {
      const localTree = {...(mode === FileFilter.PR ? diffPaths : fileTree)}
      for (const filePath of Object.keys(fileStatuses)) {
        // add files that only exist locally to the tree
        if (isAdded(fileStatuses[filePath])) {
          if (mode === FileFilter.PR) {
            addPathToTree(localTree, filePath, true)
          } else {
            addPathToTree(localTree, filePath)
          }
        }
      }

      return localTree
    },
    [diffPaths, fileStatuses, fileTree],
  )

  // Calculate diffs for new content and persist it to local storage
  const editFile = useStableCallback(
    ({
      filePath,
      originalContent,
      newFileContent,
    }: {
      filePath?: string
      originalContent?: string
      newFileContent?: string
    }) => {
      if (!filePath) return

      // try to carry over the previous file path data to the new patch object
      let oldFilePath: string
      let newFilePath: string
      const prevPatch = patches[filePath]
      if (prevPatch) {
        oldFilePath = prevPatch.oldFileName ?? ''
        newFilePath = prevPatch.newFileName ?? ''
      } else {
        oldFilePath = filePath ?? ''
        newFilePath = oldFilePath
      }

      const oldContents = originalContent ?? ''
      const newContents = newFileContent ?? oldContents

      let newPatches = undefined
      if (oldFilePath === newFilePath && oldContents === newContents) {
        // if the file is reverting back to an unmodified state, just delete the patch
        if (prevPatch) {
          newPatches = {...patches}
          delete newPatches[filePath]
        }
      } else {
        const patch = {oldContents, oldFilePath, newContents, newFilePath}
        newPatches = mergePatchesToStored([patch])
      }

      if (newPatches) {
        updatePatchesAndStatuses(newPatches)
      }
    },
  )

  const addFile = useStableCallback((filePath: string) => {
    const patch = {oldContents: '', oldFilePath: '', newContents: '', newFilePath: filePath}
    const newPatches = mergePatchesToStored([patch])
    updatePatchesAndStatuses(newPatches)
  })

  const renameFile = useStableCallback(
    ({
      oldFilePath,
      newFilePath,
      originalContent,
    }: {
      oldFilePath: string
      newFilePath: string
      originalContent: string | undefined
    }) => {
      if (oldFilePath === newFilePath) return

      const {content: currentFileContent} = getCurrentFileContent(oldFilePath, originalContent)
      const currentFileStatus = fileStatuses[oldFilePath]

      if (isAdded(currentFileStatus)) {
        // if the renamed file only exists locally, just update the patch object
        const newPatches = {...patches}
        const patch = newPatches[oldFilePath]
        if (patch) {
          delete newPatches[oldFilePath]
          newPatches[newFilePath] = {...patch, newFileName: newFilePath}
          updatePatchesAndStatuses(newPatches)
        }
      } else {
        // renames are treated as a deletion of the previous file and an addition of a new file for files
        // that exist on the server
        const deletedPatch = {oldContents: '', oldFilePath, newContents: '', newFilePath: ''}
        const addedPatch = {oldContents: '', oldFilePath: '', newContents: currentFileContent ?? '', newFilePath}
        const newPatches = mergePatchesToStored([deletedPatch, addedPatch])
        updatePatchesAndStatuses(newPatches)
      }
    },
  )

  const deleteFile = useStableCallback((filePath: string, originalContent: string | undefined) => {
    const currentFileStatus = fileStatuses[filePath]
    if (isAdded(currentFileStatus)) {
      // if the deleted file only exists locally, just remove the patch object
      const newPatches = {...patches}
      const patch = newPatches[filePath]
      if (patch) {
        delete newPatches[filePath]
        updatePatchesAndStatuses(newPatches)
      }
    } else {
      const deletedPatch = {oldContents: originalContent ?? '', oldFilePath: filePath, newContents: '', newFilePath: ''}
      const newPatches = mergePatchesToStored([deletedPatch])
      updatePatchesAndStatuses(newPatches)
    }
  })

  const markFilesCommitted = useStableCallback((files: Iterable<string>) => {
    const newPatches = {...patches}
    for (const file of files) {
      delete newPatches[file]
    }

    updatePatchesAndStatuses(newPatches)
  })

  const resetFiles = useStableCallback(() => {
    // We clear local storage directly to avoid leaving any any unneeded data behind
    // (i.e. if we called updatePatchesAndStatuses({}), we store that empty object
    // which is functionally the same but wastes space for the user)
    const storageKey = buildPatchesStorageKey(ownerLogin, name, pullRequestNumber)
    clearLocalStorage([storageKey])
    setFileStatuses({})

    resetSuggestionState()
  })

  const resetFile = useStableCallback((filePath: string) => {
    const newPatches = {...patches}
    const patch = newPatches[filePath]
    if (patch) {
      delete newPatches[filePath]
      updatePatchesAndStatuses(newPatches)
    }
  })

  return {
    addFile,
    applyAllTaskSuggestionsToContent,
    applySuggestionsToContent,
    deleteFile,
    editFile,
    getChangedFiles,
    getCurrentFileContent,
    getFileStatuses,
    getFileTreeData,
    markFilesCommitted,
    renameFile,
    resetFiles,
    resetFile,
    storeDiffs: useStableCallback((_pushableDiffs: PushableDiffs) => {
      throw new Error('Not supported without two-way file-syncer.')
    }),
    retrieveDiffs: useStableCallback(() => {
      throw new Error('Not supported without two-way file-syncer.')
    }),
  }
}

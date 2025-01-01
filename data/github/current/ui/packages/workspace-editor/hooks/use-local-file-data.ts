import {useCurrentRepository} from '@github-ui/current-repository'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useLocalStorage} from '@github-ui/use-safe-storage/local-storage'
import type {FileStatus, FileStatuses} from '@github-ui/web-commit-dialog'
import {Mutex} from 'async-mutex'
import {applyPatch} from 'diff'
import {useCallback, useRef, useState} from 'react'

import {useCurrentPullRequest} from '../contexts/CurrentPullRequestProvider'
import {useWorkspaceEditorAppContext} from '../contexts/WorkspaceEditorAppContext'
import {isAdded, isDeleted} from '../utilities/file-status-helpers'
import type {
  DiffEntry,
  ExtendedDiff,
  PersistedDiffs,
  PushableDiffs,
  SerializedDiffs,
} from '../utilities/file-syncer-types'
import {createDiffEntries} from '../utilities/patch-helpers'
import {applySuggestions, problemWithTaskSuggestions} from '../utilities/suggestion-helpers'
import {addPathToTree} from '../utilities/tree-helpers'
import {
  type BlobPayload,
  type FileDataStore,
  type FileDataWithStatus as FileData,
  FileFilter,
  type FocusedTaskData,
  type FocusedTaskSuggestion,
  type WorkspaceEditorRoutePayload,
} from '../utilities/workspace-editor-types'
import {useLocalSuggestionState} from './use-local-suggestion-state'

const mutex = new Mutex()

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

function getFileStatusesFromPatches(persistedDiffs: PersistedDiffs): FileStatuses {
  const result: FileStatuses = {}
  for (const {path, originalFileStatus, currentFileStatus, diff} of persistedDiffs.diffs) {
    if (diff.ignoreReason) {
      // ignore diffs that are not supported by the file syncer
      continue
    }

    if (originalFileStatus === 'A') {
      if (currentFileStatus === 'D') {
        // if the file was added and then deleted, ignore the patch for statuses
        continue
      } else {
        result[path] = 'A'
      }
    } else if (originalFileStatus === 'M') {
      if (currentFileStatus === 'D') {
        result[path] = 'D'
      } else {
        if (diff.hunks.length === 0) {
          // if the file was modified and then reverted, ignore the patch for statuses
          continue
        }

        result[path] = 'M'
      }
    } else if (currentFileStatus) {
      result[path] = currentFileStatus
    }
  }

  return result
}

function getDiffEntryFromPatches(filePath: string, patches: PersistedDiffs) {
  return patches.diffs.find(d => d.path === filePath)
}

function buildPatchesStorageKey(org: string, repoName: string, entityId: string) {
  return `hadron-editor-file-deltas-v2/${org}/${repoName}/${entityId}`
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
  const avoidEditSyncOptimization = useFeatureFlag('hadron_avoid_edit_sync_optimization')
  const {pullRequest} = useCurrentPullRequest()
  const {diffPaths, fileTree} = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {name, ownerLogin} = useCurrentRepository()
  const [patches, setPatches] = useLocalStorage<PersistedDiffs>(
    buildPatchesStorageKey(ownerLogin, name, pullRequest.number),
    {sessionId: '', latestTimestamp: -1, diffs: []},
  )
  const [fileStatuses, setFileStatuses] = useState<FileStatuses>(() => getFileStatusesFromPatches(patches))

  const {getAppliedSuggestions, resetSuggestionState, resetSuggestionsForFile, updateAppliedSuggestions} =
    useLocalSuggestionState()

  const {blobService} = useWorkspaceEditorAppContext()

  const convertDiffsToPersist = useStableCallback(async (pushableDiffs: PushableDiffs): Promise<PersistedDiffs> => {
    const currentState = {...patches, latestTimestamp: Date.now()}
    const MAX_API_CALLS = 20
    let apiCalls = 0

    async function calculateOriginalFileStatus(path: string): Promise<FileStatus | undefined> {
      // TODO: This is a temporary solution to avoid overloading the server while we work on a more permanent solution
      // TODO: Future improvement - do this in the background without blocking the syncing process
      if (apiCalls >= MAX_API_CALLS) {
        return undefined
      }

      const blob = await blobService.getBlob(path, ownerLogin, pullRequest.number, name, pullRequest.headSHA)
      apiCalls++
      if (blob?.ok) {
        return blob.payload.blobContents !== null ? 'M' : 'A'
      } else {
        return undefined
      }
    }

    for (const newDiff of pushableDiffs.diffs) {
      const existingDiffEntry = getDiffEntryFromPatches(newDiff.path, currentState)
      const newPatch = JSON.parse(newDiff.diff) as ExtendedDiff
      if (existingDiffEntry) {
        const newStatus = newPatch.isDeleted ? 'D' : 'M'
        existingDiffEntry.diff = newPatch
        existingDiffEntry.currentFileStatus = newStatus

        if (!existingDiffEntry.originalFileStatus) {
          existingDiffEntry.originalFileStatus = await calculateOriginalFileStatus(newDiff.path)
        }
      } else {
        const originalFileStatus = await calculateOriginalFileStatus(newDiff.path)
        currentState.diffs.push({
          path: newDiff.path,
          originalFileStatus,
          currentFileStatus: newPatch.isDeleted ? 'D' : 'M',
          diff: newPatch,
        })
      }
    }
    return currentState
  })

  const storeDiffs = useStableCallback(async (pushableDiffs: PushableDiffs) => {
    return await mutex.runExclusive(async () => {
      const newPatches = await convertDiffsToPersist(pushableDiffs)
      updatePatchesAndStatuses(newPatches)
      return newPatches
    })
  })

  const retrieveDiffs = useStableCallback(() => {
    const persistedDiffs = {...patches}
    const serializedDiffs: SerializedDiffs = {
      sessionId: persistedDiffs.sessionId,
      latestTimestamp: persistedDiffs.latestTimestamp,
      diffs: persistedDiffs.diffs.map(d => ({path: d.path, diff: JSON.stringify(d.diff)})),
    }

    return serializedDiffs
  })

  const updatePatchesAndStatuses = useStableCallback((newPatches: PersistedDiffs) => {
    newPatches.latestTimestamp = Date.now()
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
    const formattedDiffs = createDiffEntries(fileData)
    const newPatches = {...patches}
    for (const formattedDiff of formattedDiffs) {
      const path = formattedDiff.path
      const existingDiffIndex = newPatches.diffs.findIndex(d => d.path === path)
      const existingDiff = newPatches.diffs[existingDiffIndex]
      const originalFileStatus =
        (existingDiff?.originalFileStatus ?? formattedDiff.originalFileStatus) === 'A' ? 'A' : 'M'
      const newDiff: DiffEntry = {
        ...existingDiff,
        ...formattedDiff,
        originalFileStatus,
      }
      if (existingDiffIndex > -1) {
        newPatches.diffs[existingDiffIndex] = newDiff
      } else {
        newPatches.diffs.push(newDiff)
      }
    }

    return newPatches
  })

  const deletePatchesFromStored = useStableCallback((...path: string[]) => {
    const newPatches = {...patches}
    for (const p of path) {
      newPatches.diffs = [...newPatches.diffs.filter(d => d.path !== p)]
    }

    return newPatches
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
      const updatedContents: {[filePath: string]: string | undefined} = {}
      const updatedFileData: FileData[] = []
      for (const {path: filePath, blobContents: originalContent} of originals) {
        const {content: currentContent} = getCurrentFileContent(filePath, originalContent)
        const contents = applySuggestions(filePath, currentContent, suggestions)
        updatedContents[filePath] = contents
        updatedFileData.push({
          oldFilePath: filePath,
          oldContents: originalContent!,
          newFilePath: filePath,
          newContents: contents!,
          status: 'M',
        })
      }

      const newPatches = mergePatchesToStored(updatedFileData)
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
    const patch = getDiffEntryFromPatches(filePath, patches)?.diff
    const result = {
      content: originalContent,
      patchIncluded: false,
      patch,
    }

    if (!patch) {
      return result
    }

    if (patch.ignoreReason) {
      // eslint-disable-next-line no-console
      console.log(`Ignoring diff for ${filePath}: ${patch.ignoreReason}`)
      return {
        ...result,
        patch: undefined,
      }
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
      const diffEntry = getDiffEntryFromPatches(path, patches)

      return {
        path,
        status: fileStatuses[path],
        patch: diffEntry!.diff,
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
        if (isDeleted(fileStatuses[filePath]) && mode === FileFilter.All) {
          addPathToTree(localTree, filePath)
        }
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
      const prevPatch = getDiffEntryFromPatches(filePath, patches)?.diff
      if (prevPatch) {
        oldFilePath = prevPatch.oldFileName ?? ''
        newFilePath = prevPatch.newFileName ?? ''
      } else {
        oldFilePath = filePath ?? ''
        newFilePath = oldFilePath
      }

      const oldContents = originalContent ?? ''
      const newContents = newFileContent ?? oldContents

      let newPatches = {...patches}
      if (avoidEditSyncOptimization) {
        newPatches = mergePatchesToStored([{oldContents, oldFilePath, newContents, newFilePath, status: 'M'}])
      } else {
        if (oldFilePath === newFilePath && oldContents === newContents) {
          // if the file is reverting back to an unmodified state, just delete the patch
          newPatches = deletePatchesFromStored(filePath)
        } else {
          newPatches = mergePatchesToStored([{oldContents, oldFilePath, newContents, newFilePath, status: 'M'}])
        }
      }

      if (newPatches) {
        updatePatchesAndStatuses(newPatches)
      }
    },
  )

  const addFile = useStableCallback((filePath: string) => {
    const patch: FileData = {oldContents: '', oldFilePath: '', newContents: '', newFilePath: filePath, status: 'A'}
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

      const deletedPatch: FileData = {
        oldContents: originalContent ?? '',
        oldFilePath,
        newContents: '',
        newFilePath: '',
        status: 'D',
      }
      const addedPatch: FileData = {
        oldContents: '',
        oldFilePath: '',
        newContents: currentFileContent || '',
        newFilePath,
        status: 'A',
      }
      const newPatches = mergePatchesToStored([deletedPatch, addedPatch])
      updatePatchesAndStatuses(newPatches)
    },
  )

  const deleteFile = useStableCallback((filePath: string, originalContent: string | undefined) => {
    const deletedPatch: FileData = {
      oldContents: originalContent ?? '',
      oldFilePath: filePath,
      newContents: '',
      newFilePath: '',
      status: 'D',
    }
    const newPatches = mergePatchesToStored([deletedPatch])
    updatePatchesAndStatuses(newPatches)
  })

  /**
   * TODO: Probably this is not enough.
   * We should probably:
   * - Stop the file syncer on codespace
   * - Reset changes in the codesapce and checkout the new commit
   * - Restart the file syncer
   * OR
   * - Re-create the codespace from latest commit
   */
  const markFilesCommitted = useStableCallback((files: Iterable<string>) => {
    // remove all diffs that has a matching path in the files to mark as committed
    const newPatches = deletePatchesFromStored(...files)
    updatePatchesAndStatuses(newPatches)
    resetSuggestionState()
  })

  const resetDiff = useStableCallback((diff: DiffEntry) => {
    if (diff.originalFileStatus === 'A') {
      // Delete the files that were added but not committed
      diff.currentFileStatus = 'D'
      diff.diff.isDeleted = true
    } else {
      diff.currentFileStatus = diff.originalFileStatus ?? 'M'
      diff.diff.isDeleted = false
      diff.diff.hunks = []
    }
  })

  const resetFiles = useStableCallback(() => {
    const newPatches = {...patches}
    for (const diff of newPatches.diffs) {
      resetDiff(diff)
    }

    updatePatchesAndStatuses(newPatches)
    resetSuggestionState()
  })

  const resetFile = useStableCallback((filePath: string) => {
    const newPatches = {...patches}
    const diff = getDiffEntryFromPatches(filePath, newPatches)
    if (!diff) return
    resetDiff(diff)

    updatePatchesAndStatuses(newPatches)
    resetSuggestionsForFile(filePath)
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
    storeDiffs,
    retrieveDiffs,
  }
}

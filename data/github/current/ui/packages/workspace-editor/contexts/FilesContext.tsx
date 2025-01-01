import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useFileTreeControlContext} from '@github-ui/repos-file-tree-view'
import {createContext, type PropsWithChildren, useCallback, useContext, useMemo} from 'react'

import {useLocalFileData} from '../hooks/use-local-file-data'
import {assertDefined} from '../utilities/asserts'
import {isAdded, isDeleted} from '../utilities/file-status-helpers'
import type {PushableDiffs} from '../utilities/file-syncer-types'
import {addPathToTree, removePathFromTree, removePathsFromTree} from '../utilities/tree-helpers'
import type {FileDataStore, WorkspaceEditorRoutePayload} from '../utilities/workspace-editor-types'
import {useCurrentPullRequest} from './CurrentPullRequestProvider'

export type FilesContextData = {
  getNewFilePaths(): string[]
} & FileDataStore

export const FilesContext = createContext<FilesContextData | undefined>(undefined)

export function FilesContextProvider({children}: PropsWithChildren) {
  const payload = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {pullRequest} = useCurrentPullRequest()
  const {
    addFile,
    applyAllTaskSuggestionsToContent,
    applyFileToContent,
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
  } = useLocalFileData()
  const {setRefreshTree} = useFileTreeControlContext()

  const addFileWrapped = useCallback(
    (path: string) => {
      setRefreshTree?.(true)
      addFile(path)
    },
    [addFile, setRefreshTree],
  )

  const renameFileWrapped = useCallback(
    ({
      oldFilePath,
      newFilePath,
      originalContent,
    }: {
      oldFilePath: string
      newFilePath: string
      originalContent: string | undefined
    }) => {
      const fileStatuses = getFileStatuses()
      const isAddedLocally = isAdded(fileStatuses[oldFilePath])

      // file tree is additive so we need to reset the tree to remove deleted files in the case where a file is renamed
      // multiple times in the same session - we don't want to continue showing intermediary files that are now gone.
      setRefreshTree?.(true)
      if (isAddedLocally) {
        removePathFromTree(payload.fileTree, oldFilePath)
      }

      renameFile({oldFilePath, newFilePath, originalContent})
    },
    [getFileStatuses, payload.fileTree, renameFile, setRefreshTree],
  )

  const deleteFileWrapped = useCallback(
    (path: string, content: string | undefined) => {
      const fileStatuses = getFileStatuses()
      const isAddedLocally = isAdded(fileStatuses[path])

      // file tree is additive so we need to reset the tree to remove deleted files
      // that only existed locally
      setRefreshTree?.(true)
      if (isAddedLocally) {
        removePathFromTree(payload.fileTree, path)
      }

      deleteFile(path, content)
    },
    [deleteFile, getFileStatuses, payload.fileTree, setRefreshTree],
  )

  const markFilesCommittedWrapped = useCallback(
    (files: Iterable<string>) => {
      // file tree is additive so we need to reset the tree to remove deleted files
      setRefreshTree?.(true)

      // try to update local state to reflect new statuses
      const fileStatuses = getFileStatuses()
      const deletedFiles = Object.keys(fileStatuses).filter(path => isDeleted(fileStatuses[path]))
      const addedFiles = Object.keys(fileStatuses).filter(path => isAdded(fileStatuses[path]))

      // make sure added files stay in the tree
      for (const addedFile of addedFiles) {
        addPathToTree(payload.fileTree, addedFile)
        if (payload.diffPaths) addPathToTree(payload.diffPaths, addedFile, true)
      }

      const localChangesOnly = payload.compareRef === pullRequest.headBranch
      if (localChangesOnly) {
        // added files now have no status, so don't need to update their status
        // deleted files are gone, so remove them from the tree
        for (const deletedFile of deletedFiles) {
          removePathFromTree(payload.fileTree, deletedFile)
          if (payload.diffPaths) removePathFromTree(payload.diffPaths, deletedFile)
        }
      } else {
        // any comparison other than against the PR's head
        if (payload.fileStatuses) {
          // added files will always have that status on the diff after committing
          for (const addedFile of addedFiles) {
            // eslint-disable-next-line react-compiler/react-compiler
            payload.fileStatuses[addedFile] = 'A'
          }

          for (const deletedFile of deletedFiles) {
            if (isAdded(payload.fileStatuses[deletedFile])) {
              // if the file is added in the PR, once we commit the deletion it's no longer in the diff at all
              // so we just remove it from the tree
              removePathFromTree(payload.fileTree, deletedFile)
              if (payload.diffPaths) removePathFromTree(payload.diffPaths, deletedFile)
            } else {
              // otherwise, the file should still show as deleted in the tree
              payload.fileStatuses[deletedFile] = 'D'
            }
          }
        }
      }

      markFilesCommitted(files)
    },
    [
      getFileStatuses,
      markFilesCommitted,
      payload.compareRef,
      payload.diffPaths,
      payload.fileStatuses,
      payload.fileTree,
      pullRequest.headBranch,
      setRefreshTree,
    ],
  )

  const resetFilesWrapped = useCallback(() => {
    // remove locally added files from the tree - once a reset happens, they're gone
    const fileStatuses = getFileStatuses()
    const addedFiles = Object.keys(fileStatuses).filter(path => isAdded(fileStatuses[path]))
    if (addedFiles.length > 0) {
      // file tree is additive so we need to reset the tree to remove local-only files that are gone
      setRefreshTree?.(true)
      removePathsFromTree(payload.fileTree, addedFiles)
    }

    resetFiles()
  }, [getFileStatuses, payload.fileTree, resetFiles, setRefreshTree])

  const resetFileWrapped = useCallback(
    (filePath: string) => {
      if (isAdded(getFileStatuses()[filePath])) {
        // file tree is additive so we need to reset the tree to remove local-only files that are gone
        setRefreshTree?.(true)
        removePathFromTree(payload.fileTree, filePath)
      }
      resetFile(filePath)
    },
    [getFileStatuses, payload.fileTree, resetFile, setRefreshTree],
  )

  const getNewFilePaths = useCallback(() => {
    const fileStatuses = getFileStatuses()
    return Object.keys(fileStatuses).filter(path => isAdded(fileStatuses[path]))
  }, [getFileStatuses])

  const storeDiffsWrapped = useCallback(
    async (diffs: PushableDiffs) => {
      const storedDiffs = await storeDiffs(diffs)
      const hasDeletion = storedDiffs.diffs.some(diff => diff.currentFileStatus === 'D')
      if (hasDeletion) {
        setRefreshTree?.(true)
      }
      return storedDiffs
    },
    [setRefreshTree, storeDiffs],
  )

  const filesContextData = useMemo(
    () => ({
      addFile: addFileWrapped,
      applyAllTaskSuggestionsToContent,
      applyFileToContent,
      applySuggestionsToContent,
      deleteFile: deleteFileWrapped,
      editFile,
      getChangedFiles,
      getCurrentFileContent,
      getFileStatuses,
      getFileTreeData,
      getNewFilePaths,
      markFilesCommitted: markFilesCommittedWrapped,
      renameFile: renameFileWrapped,
      resetFile: resetFileWrapped,
      resetFiles: resetFilesWrapped,
      storeDiffs: storeDiffsWrapped,
      retrieveDiffs,
    }),
    [
      addFileWrapped,
      applyAllTaskSuggestionsToContent,
      applyFileToContent,
      applySuggestionsToContent,
      deleteFileWrapped,
      editFile,
      getChangedFiles,
      getCurrentFileContent,
      getFileStatuses,
      getFileTreeData,
      getNewFilePaths,
      markFilesCommittedWrapped,
      renameFileWrapped,
      resetFileWrapped,
      resetFilesWrapped,
      storeDiffsWrapped,
      retrieveDiffs,
    ],
  )

  return <FilesContext.Provider value={filesContextData}>{children}</FilesContext.Provider>
}

export function useFilesContext() {
  const context = useContext(FilesContext)
  assertDefined(context, 'useFilesContext must be used within a FilesContextProvider.')

  return context
}

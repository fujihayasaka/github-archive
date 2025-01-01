import {useCallback} from 'react'

import {useFilesContext} from '../contexts/FilesContext'
import {useFileSyncerContext} from '../contexts/FileSyncerContext'

export function useFileUpdates() {
  const {editFile, deleteFile} = useFilesContext()

  const {forceContentRefresh} = useFileSyncerContext()

  const applyEdit = useCallback(
    async (filePath: string, content: string | undefined, originalContent: string | undefined) => {
      await editFile({filePath, newFileContent: content, originalContent})
      forceContentRefresh()
    },
    [editFile, forceContentRefresh],
  )

  const applyDelete = useCallback(
    async (filePath: string) => {
      deleteFile(filePath, '')
    },
    [deleteFile],
  )

  return {applyEdit, applyDelete}
}

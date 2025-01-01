import {assertDefined} from '@github-ui/workspace-editor/utilities/asserts'
import {createContext, type PropsWithChildren, useCallback, useContext, useEffect, useMemo, useState} from 'react'

import type {FileEntry} from '../types/file-syncer-v2-types'
import {useFileSyncerContext} from './FileSyncerContext'

export const DEFAULT_FILES = ['index.html', 'src/App.tsx', 'src/index.css']

export type FilesContextData = {
  deleteFile: (path: string, originalContent: string | undefined) => Promise<void>
  editFile: (args: {
    filePath: string
    originalContent?: string
    newFilePath?: string
    newFileContent?: string
  }) => Promise<void>
  getFileList: () => FileEntry[]
  writeFileBytes: (args: {filePath: string; content: Uint8Array}) => Promise<void>
}

export const FilesContext = createContext<FilesContextData | undefined>(undefined)

export function FilesContextProvider({children}: PropsWithChildren) {
  const {fileSyncerStarted, fileTreeStateStamp, getFileSyncerV2, notifyEdited} = useFileSyncerContext()
  const [filesV2, setFilesV2] = useState<FileEntry[]>([])

  const tryFileSyncer = useCallback(() => {
    if (!fileSyncerStarted) {
      return
    }

    return getFileSyncerV2()
  }, [fileSyncerStarted, getFileSyncerV2])

  // This effect is intended to run initially on file syncer start up
  // and when we force refresh the file tree.
  useEffect(() => {
    if (!fileSyncerStarted) {
      return
    }
    fetchFileEntries()
    async function fetchFileEntries() {
      const fileSyncer = getFileSyncerV2()
      if (!fileSyncer) {
        return
      }

      try {
        setFilesV2(await fileSyncer.getDirectoryContents('.'))
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error('Error fetching file entries:', error)
      }
    }
    // fileTreeStateStamp is unused in the hook, but is our external trigger so make sure it's there!
  }, [fileTreeStateStamp, fileSyncerStarted, getFileSyncerV2])

  const editFileWrapped = useCallback(
    async ({filePath, newFileContent}: {filePath: string; newFileContent?: string}) => {
      await tryFileSyncer()?.writeFileString(filePath, newFileContent ?? '')
      notifyEdited()
    },
    [notifyEdited, tryFileSyncer],
  )

  const writeFileBytesWrapped = useCallback(
    async ({filePath, content}: {filePath: string; content: Uint8Array}) => {
      await tryFileSyncer()?.writeFileBytes(filePath, content)
      notifyEdited()
    },
    [notifyEdited, tryFileSyncer],
  )

  const deleteFileWrapped = useCallback(
    async (path: string, _content: string | undefined) => {
      await tryFileSyncer()?.deleteFile(path)
    },
    [tryFileSyncer],
  )

  const getFileList = useCallback(() => {
    return filesV2
  }, [filesV2])

  const filesContextData = useMemo(
    () => ({
      deleteFile: deleteFileWrapped,
      editFile: editFileWrapped,
      getFileList,
      writeFileBytes: writeFileBytesWrapped,
    }),
    [deleteFileWrapped, editFileWrapped, getFileList, writeFileBytesWrapped],
  )

  return <FilesContext.Provider value={filesContextData}>{children}</FilesContext.Provider>
}

export function useFilesContext() {
  const context = useContext(FilesContext)
  assertDefined(context, 'useFilesContext must be used within a FilesContextProvider.')

  return context
}

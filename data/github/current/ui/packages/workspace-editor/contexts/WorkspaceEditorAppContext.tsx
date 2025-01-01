import {createContext, type PropsWithChildren, useContext, useMemo, useRef} from 'react'

import {BlobService} from '../utilities/blob-service'

interface WorkspaceEditorAppContextData {
  blobService: BlobService
}

/**
 * Context that holds global static app state
 */
const WorkspaceEditorAppContext = createContext<WorkspaceEditorAppContextData | undefined>(undefined)

export function WorkspaceEditorAppContextProvider({children}: PropsWithChildren) {
  const blobService = useRef(new BlobService())

  // eslint-disable-next-line react-compiler/react-compiler
  const value = useMemo(() => ({blobService: blobService.current}), [blobService])

  return <WorkspaceEditorAppContext.Provider value={value}>{children}</WorkspaceEditorAppContext.Provider>
}

export function useWorkspaceEditorAppContext() {
  const context = useContext(WorkspaceEditorAppContext)
  if (!context) {
    throw new Error('useWorkspaceEditorAppContext must be used within an WorkspaceEditorAppContextProvider')
  }
  return context
}

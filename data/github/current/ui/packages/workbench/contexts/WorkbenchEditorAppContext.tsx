import {createContext, type PropsWithChildren, useContext, useMemo, useRef} from 'react'

import {BlobService} from '../utilities/blob-service'

interface WorkbenchEditorAppContextData {
  blobService: BlobService
}

/**
 * Context that holds global static app state
 */
const WorkbenchEditorAppContext = createContext<WorkbenchEditorAppContextData | undefined>(undefined)

export function WorkbenchEditorAppContextProvider({children}: PropsWithChildren) {
  const blobService = useRef(new BlobService())

  // eslint-disable-next-line react-compiler/react-compiler
  const value = useMemo(() => ({blobService: blobService.current}), [blobService])

  return <WorkbenchEditorAppContext.Provider value={value}>{children}</WorkbenchEditorAppContext.Provider>
}

export function useWorkbenchEditorAppContext() {
  const context = useContext(WorkbenchEditorAppContext)
  if (!context) {
    throw new Error('useWorkbenchEditorAppContext must be used within an WorkbenchEditorAppContextProvider')
  }
  return context
}

import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {ConnectedCodespaceData} from '@github-ui/workspace-editor/utilities/workspace-editor-types'
import React, {useContext, useEffect, useMemo} from 'react'

import {useCodespaces} from '../lsp/use-codespaces'
import type {WorkbenchRoutePayload} from '../types/workbench-types'
import {useWorkbenchStore} from './WorkbenchStoreContext'

export type CodespaceContext = {
  codespaceData: ConnectedCodespaceData
}

export const CodespaceContext = React.createContext<CodespaceContext | undefined>(undefined)

// The CodespaceContext is responsible for managing the codespace data for the Workbench's current codespace. Pass
// this context to components that require access to the codespace info.
export function CodespaceContextProvider({children}: React.PropsWithChildren) {
  // TODO: Spark Workbench is moving away from repos, this dependency should be replaced with something
  // else eventually
  const payload = useRoutePayload<WorkbenchRoutePayload>()
  const {repo} = payload
  const codespaceData = useCodespaces(repo)
  const {onCodespaceStatus} = useWorkbenchStore()

  useEffect(() => {
    onCodespaceStatus(codespaceData.codespaceState)
  }, [codespaceData.codespaceState, onCodespaceStatus])

  // TODO: Do we need logic here to handle the case where the codespace is not yet provisioned? Or an error occurs?
  // This might be handled by the useCodespaces hook
  const value = useMemo(
    () => ({
      codespaceData,
    }),
    [codespaceData],
  )

  return <CodespaceContext.Provider value={value}>{children}</CodespaceContext.Provider>
}

export function useCodespaceContext() {
  const context = useContext(CodespaceContext)
  if (!context) {
    throw new Error('useCodespaceContext must be used within a CodespaceContextProvider')
  }
  return context
}

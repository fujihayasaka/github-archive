import {isFeatureEnabled} from '@github-ui/feature-flags'
import React, {useContext, useMemo} from 'react'

import {useWorkbenchStore} from './WorkbenchStoreContext'

export const ReadOnlyContext = React.createContext<boolean>(false)

export function ReadOnlyProvider({readOnly, children}: React.PropsWithChildren<{readOnly: boolean}>) {
  const parentReadOnly = useContext(ReadOnlyContext)
  const value = useMemo<boolean>(() => parentReadOnly || readOnly, [parentReadOnly, readOnly])
  return <ReadOnlyContext.Provider value={value}>{children}</ReadOnlyContext.Provider>
}

export function useReadOnly() {
  const context = useContext(ReadOnlyContext)
  const {readOnly} = useWorkbenchStore()

  if (!isFeatureEnabled('workbench_store_readonly')) {
    return false
  }

  if (readOnly) {
    return true
  }
  if (!context) {
    // eslint-disable-next-line no-console
    console.warn('Could not find ReadOnlyProvider, defaulting to false')
    return false
  }
  return context
}

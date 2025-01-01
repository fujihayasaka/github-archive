import React, {useContext} from 'react'

import {useTargetedEdits} from '../targeted-edits/use-targeted-edits'

export type TargetedEditsContext = ReturnType<typeof useTargetedEdits>

export const TargetedEditsContext = React.createContext<TargetedEditsContext | undefined>(undefined)

export function TargetedEditsProvider({children}: React.PropsWithChildren) {
  const value = useTargetedEdits()

  return <TargetedEditsContext.Provider value={value}>{children}</TargetedEditsContext.Provider>
}

export function useTargetedEditsContext() {
  const context = useContext(TargetedEditsContext)
  if (!context) {
    throw new Error('useTargetedEditsContext must be used within a TargetedEditsProvider')
  }
  return context
}

import {createContext, type PropsWithChildren, useContext} from 'react'
import invariant from 'tiny-invariant'
import type {PlaygroundManager} from '../utils/playground-manager'

export const PlaygroundManagerContext = createContext<PlaygroundManager | null>(null)

export function usePlaygroundManager() {
  const context = useContext(PlaygroundManagerContext)
  invariant(context, 'usePlaygroundManager must be used within a PlaygroundManagerProvider')
  return context
}

export const PlaygroundManagerProvider = ({manager, children}: PropsWithChildren<{manager: PlaygroundManager}>) => {
  return <PlaygroundManagerContext.Provider value={manager}>{children}</PlaygroundManagerContext.Provider>
}

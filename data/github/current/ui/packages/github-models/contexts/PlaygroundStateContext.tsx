import {createContext, type PropsWithChildren, useContext} from 'react'
import type {ModelState, PlaygroundState} from '../types'

export const initialPlaygroundState = (): PlaygroundState => ({
  selectedLanguage: 'js',
  selectedSDK: '',
  syncInputs: false,
  models: [] as ModelState[],
})

const PlaygroundStateContext = createContext<PlaygroundState>(initialPlaygroundState())

export function usePlaygroundState() {
  return useContext(PlaygroundStateContext)
}

export const PlaygroundStateProvider = ({children, state}: PropsWithChildren<{state: PlaygroundState}>) => {
  return <PlaygroundStateContext.Provider value={state}>{children}</PlaygroundStateContext.Provider>
}

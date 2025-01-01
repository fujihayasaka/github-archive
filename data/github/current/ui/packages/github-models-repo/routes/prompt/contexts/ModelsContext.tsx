import {createContext, useContext, type PropsWithChildren} from 'react'
import type {RepoModel} from '../../../types'

const ModelsContext = createContext<RepoModel[]>([])

export function useModels() {
  return useContext(ModelsContext)
}

export const ModelsProvider = ({children, models}: PropsWithChildren<{models: RepoModel[]}>) => {
  return <ModelsContext.Provider value={models}>{children}</ModelsContext.Provider>
}

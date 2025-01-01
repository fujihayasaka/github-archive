import type {Model} from '@github-ui/marketplace-common'
import {createContext, useContext, type PropsWithChildren} from 'react'

const ModelsContext = createContext<Model[]>([])

export function useModels() {
  return useContext(ModelsContext)
}

export const ModelsProvider = ({children, models}: PropsWithChildren<{models: Model[]}>) => {
  return <ModelsContext.Provider value={models}>{children}</ModelsContext.Provider>
}

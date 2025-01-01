import {createContext, useContext} from 'react'
import type {PipesService} from '../service/pipes-service'

const PipesServiceContext = createContext<PipesService | null>(null)

export const PipesServiceProvider = PipesServiceContext.Provider

export function usePipesService(): PipesService {
  const s = useContext(PipesServiceContext)
  if (!s) throw new Error('usePipesService must be used inside a PipesServiceProvider')
  return s
}

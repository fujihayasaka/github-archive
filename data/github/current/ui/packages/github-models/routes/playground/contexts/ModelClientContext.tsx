import {createContext, type PropsWithChildren, useContext} from 'react'
import type {AzureModelClient} from '../../../utils/azure-model-client'
import invariant from 'tiny-invariant'

const ModelClientContext = createContext<AzureModelClient | null>(null)

export const ModelClientProvider = ({modelClient, children}: PropsWithChildren<{modelClient: AzureModelClient}>) => {
  return <ModelClientContext.Provider value={modelClient}>{children}</ModelClientContext.Provider>
}

export function useModelClient() {
  const context = useContext(ModelClientContext)
  invariant(context, 'Expected a ModelClientProvider')
  return context
}

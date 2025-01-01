import type {PropsWithChildren} from 'react'
import {createContext, useContext, useEffect, useMemo, useState} from 'react'

import {MergeMethod} from '../types'
import {useMergeBoxPageDataQueryKey} from '../page-data/loaders/use-merge-box-page-data'
import {useQueryClient} from '@github-ui/react-query'

interface MergeMethodContextData {
  mergeMethod: MergeMethod
  setMergeMethod: (mergeMethod: MergeMethod) => void
}

export const MergeMethodContext = createContext<MergeMethodContextData>({
  mergeMethod: MergeMethod.MERGE,
  setMergeMethod: () => {},
})

export function MergeMethodContextProvider({
  children,
  defaultMergeMethod,
}: PropsWithChildren<{defaultMergeMethod: MergeMethod}>) {
  const [mergeMethod, setMergeMethod] = useState<MergeMethod>(defaultMergeMethod)
  const mergeBoxPageDataQueryKey = useMergeBoxPageDataQueryKey()
  const queryClient = useQueryClient()

  useEffect(() => {
    // Refetch MergeBox data when merge method changes
    queryClient.invalidateQueries({queryKey: mergeBoxPageDataQueryKey})
    // We don't want this useEffect to listen to dynamic Tan Stack Query Keys
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mergeMethod])

  const value = useMemo(
    () => ({
      mergeMethod,
      setMergeMethod,
    }),
    [mergeMethod],
  )

  return <MergeMethodContext.Provider value={value}>{children}</MergeMethodContext.Provider>
}

export function useMergeMethodContext(): MergeMethodContextData {
  const contextData = useContext(MergeMethodContext)
  return contextData
}

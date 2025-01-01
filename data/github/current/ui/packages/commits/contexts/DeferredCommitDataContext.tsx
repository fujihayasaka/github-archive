import type React from 'react'
import {createContext, useContext} from 'react'

import type {DeferredData} from '../types/commits-types'

export const baseEmptyStateLoading: DeferredData = {
  deferredCommits: [],
  renameHistory: null,
  loading: true,
}

export const baseEmptyStateNotLoading: DeferredData = {
  deferredCommits: [],
  renameHistory: null,
  loading: false,
}

const DeferredCommitDataContext = createContext<DeferredData>(baseEmptyStateLoading)

export function DeferredCommitDataProvider({
  children,
  deferredData,
}: React.PropsWithChildren<{deferredData: DeferredData}>) {
  return <DeferredCommitDataContext.Provider value={deferredData}>{children}</DeferredCommitDataContext.Provider>
}

export function useFindDeferredCommitData(oid: string) {
  const deferredData = useContext(DeferredCommitDataContext)

  const isError = deferredData.error
  //this will never be null in the actual execution of the code, but having the '?' makes testing everything
  //significantly easier.
  let commitDataForOid = deferredData.deferredCommits?.find(data => data?.oid === oid)
  if (isError && commitDataForOid === undefined) {
    commitDataForOid = {oid, statusCheckStatus: undefined}
  }
  return commitDataForOid
}

export function useIsDeferredDataLoading() {
  const deferredData = useContext(DeferredCommitDataContext)
  return deferredData.loading
}

export function useRenameHistoryData() {
  const deferredData = useContext(DeferredCommitDataContext)

  return deferredData.renameHistory
}

import type {PropsWithChildren} from 'react'
import {createContext, useContext, useMemo} from 'react'

import {parseCommitRange} from '../utils/parse-commit-range'

interface SelectedRefContextData {
  startOid?: string | null
  endOid?: string | null
  baseRefOid?: string
}

export const SelectedRefContext = createContext<SelectedRefContextData>({})

export function SelectedRefContextProvider({
  baseRefOid,
  path,
  children,
}: PropsWithChildren<{baseRefOid?: string; path: string}>) {
  const value = useMemo(() => {
    const pathParts = path.split('/')
    const last = pathParts[pathParts.length - 1]

    let startOid: string | undefined
    let endOid: string | undefined
    if (last) {
      const pathCommitData = parseCommitRange(last)
      if (pathCommitData) {
        startOid = 'startOid' in pathCommitData ? pathCommitData.startOid : baseRefOid
        endOid = 'endOid' in pathCommitData ? pathCommitData.endOid : pathCommitData.singleCommitOid
      }
    }

    return {
      endOid,
      startOid,
      baseRefOid,
    }
  }, [baseRefOid, path])

  return <SelectedRefContext.Provider value={value}>{children}</SelectedRefContext.Provider>
}

export const useSelectedRefContext = () => useContext(SelectedRefContext)

export function useHasCommitRange() {
  const {endOid, startOid} = useSelectedRefContext()
  return !!endOid || !!startOid
}

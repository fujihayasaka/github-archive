import type React from 'react'
import {createContext, useCallback, useContext, useEffect, useMemo, useState} from 'react'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {useCalculatedMax} from './CalculatedMaxContext'
import {addUrlToHistoryStack} from '@github-ui/history'

/**
 * Retrieves dates (as milliseconds since the epoch) from the `from` and `to` query parms.
 */
function readDateFromUrl(): {from?: number; to?: number} {
  const from = new URL(ssrSafeLocation.href, ssrSafeLocation.origin).searchParams.get('from')
  const to = new URL(ssrSafeLocation.href, ssrSafeLocation.origin).searchParams.get('to')
  return {from: from ? new Date(from).getTime() : undefined, to: to ? new Date(to).getTime() : undefined}
}

/**
 * Writes dates (formatted as YYYY-MM-DD strings) to the `from` and `to` query parms.
 */
function writeDateToUrl(date: {from?: number; to?: number}): void {
  const from = date.from ? new Date(date.from).toLocaleDateString() : undefined
  const to = date.to ? new Date(date.to).toLocaleDateString() : undefined
  const url = new URL(window.location.href, window.location.origin)
  if (from) {
    url.searchParams.set('from', from)
  } else {
    url.searchParams.delete('from')
  }
  if (to) {
    url.searchParams.set('to', to)
  } else {
    url.searchParams.delete('to')
  }
  addUrlToHistoryStack(url.toString())
}

export type RangeSelectionContextValues = {
  /** Earliest chart date, in milliseconds since the epoch */
  from?: number
  /** Latest chart date, in milliseconds since the epoch */
  to?: number
  /** Updates `from` and `to` in React state */
  setDate: (date: {from?: number; to?: number}) => void
}

type SetDateProps = Pick<RangeSelectionContextValues, 'from' | 'to'>

export const RangeSelectionContext = createContext<RangeSelectionContextValues>({} as RangeSelectionContextValues)

// This follows the “Extracting providers to a component” example in https://react.dev/reference/react/useContext#extracting-providers-to-a-component. This pattern keep context-specific state and effects in one place.
export function RangeSelectionProvider({children}: React.PropsWithChildren) {
  // Read dates from the URL on initial render
  const [{from, to}, setDate] = useState<SetDateProps>(() => readDateFromUrl())
  const {reset} = useCalculatedMax()

  const wrappedSetDate = useCallback(
    (args: SetDateProps) => {
      reset()
      setDate(args)
    },
    [reset, setDate],
  )

  // When dates change, update the URL
  useEffect(() => {
    writeDateToUrl({from, to})
  }, [from, to])

  const dateProviderValue = useMemo(
    () => ({
      from,
      to,
      setDate: wrappedSetDate,
    }),
    [from, to, wrappedSetDate],
  )

  return <RangeSelectionContext.Provider value={dateProviderValue}>{children}</RangeSelectionContext.Provider>
}

export function useRangeSelection() {
  return useContext(RangeSelectionContext)
}

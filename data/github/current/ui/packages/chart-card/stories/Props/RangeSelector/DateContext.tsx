import type React from 'react'
import {createContext, useEffect, useMemo, useState} from 'react'
import {toYYYYMMDD} from './toYYYYMMDD'

/**
 * Retrieves dates (as milliseconds since the epoch) from the `from` and `to` query parms.
 */
function readDateFromUrl(): {from?: number; to?: number} {
  const from = new URL(window.location.href, window.location.origin).searchParams.get('from')
  const to = new URL(window.location.href, window.location.origin).searchParams.get('to')
  return {from: from ? new Date(from).getTime() : undefined, to: to ? new Date(to).getTime() : undefined}
}

/**
 * Writes dates (formatted as YYYY-MM-DD strings) to the `from` and `to` query parms.
 */
function writeDateToUrl(date: {from?: number; to?: number}): void {
  const from = toYYYYMMDD(date.from)
  const to = toYYYYMMDD(date.to)
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
  window.history.pushState({}, '', url.toString())
}

export type DateContextValues = {
  /** Earliest chart date, in milliseconds since the epoch */
  from?: number
  /** Latest chart date, in milliseconds since the epoch */
  to?: number
  /** Updates `from` and `to` in React state */
  setDate: (date: {from?: number; to?: number}) => void
}

export const DateContext = createContext<DateContextValues>({} as DateContextValues)

// This follows the “Extracting providers to a component” example in https://react.dev/reference/react/useContext#extracting-providers-to-a-component. This pattern keep context-specific state and effects in one place.
export function DateProvider({children}: React.PropsWithChildren) {
  // Read dates from the URL on initial render
  const [{from, to}, setDate] = useState<{from?: number; to?: number}>(() => readDateFromUrl())

  // When dates change, update the URL
  useEffect(() => {
    writeDateToUrl({from, to})
  }, [from, to])

  const dateProviderValue = useMemo(
    () => ({
      from,
      to,
      setDate,
    }),
    [from, to, setDate],
  )

  return <DateContext.Provider value={dateProviderValue}>{children}</DateContext.Provider>
}

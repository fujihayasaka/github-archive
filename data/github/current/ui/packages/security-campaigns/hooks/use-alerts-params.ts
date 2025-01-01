import {useSearchParams} from '@github-ui/use-navigate'
import {useCallback, useState} from 'react'
import {parseCursor, serializeCursor, type Cursor} from '../types/cursor'
import {parseAlertsGroup, type AlertsGroup} from '../types/get-alerts-groups-request'

export const openAlertsQuery = 'is:open'
export const closedAlertsQuery = 'is:closed'
export const defaultQuery = openAlertsQuery

type UseAlertsParamsOptions = {
  initialQuery?: string
  initialGroup?: AlertsGroup
}

export function useAlertsParams({initialGroup, initialQuery = defaultQuery}: UseAlertsParamsOptions = {}) {
  const [params, setParams] = useSearchParams()
  const [query, setQuery] = useState<string>(() => params.get('query') || initialQuery)
  const [cursor, setCursor] = useState<Cursor | null>(() => parseCursor(params))
  const [group, setGroup] = useState<AlertsGroup>(() => parseAlertsGroup(params.get('group'), initialGroup))

  // Changing the query also resets the cursor.
  // Calling setParams twice in one render doesn't appear to work correctly so we need to do it in a single call.
  const onQueryChange = useCallback(
    (newQuery: string) => {
      setQuery(newQuery)
      setCursor(null)
      setParams(prevParams => {
        const next = new URLSearchParams(prevParams)
        next.set('query', newQuery)
        next.delete('before')
        next.delete('after')
        return next
      })
    },
    [setParams],
  )

  const onCursorChange = useCallback(
    (newCursor: Cursor | null) => {
      setCursor(newCursor)
      setParams(prevParams => {
        const next = new URLSearchParams(prevParams)
        serializeCursor(newCursor, next)
        return next
      })
    },
    [setParams],
  )

  const onGroupChange = useCallback(
    (v: AlertsGroup) => {
      setGroup(v)
      setCursor(null)
      setParams(prevParams => {
        const next = new URLSearchParams(prevParams)
        next.set('group', v)
        next.delete('before')
        next.delete('after')
        return next
      })
    },
    [setGroup, setParams],
  )

  const onStateFilterChange = useCallback(
    (state: 'open' | 'closed') => {
      const queryWithoutState = query.replaceAll(/is:(open|closed)/g, '').trim()
      onQueryChange(`is:${state} ${queryWithoutState}`.trim())
    },
    [query, onQueryChange],
  )

  const showRevert = query.trim() !== initialQuery
  const revertQuery = useCallback(() => onQueryChange(initialQuery), [onQueryChange, initialQuery])

  return {
    query,
    cursor,
    group,
    onQueryChange,
    onCursorChange,
    onGroupChange,
    onStateFilterChange,
    showRevert,
    revertQuery,
  }
}

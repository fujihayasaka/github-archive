import {useSearchParams} from '@github-ui/use-navigate'
import {useCallback, useState} from 'react'
import {defaultQuery} from '../components/AlertsList'
import {parseAlertsCursor, serializeAlertsCursor, type AlertsCursor} from '../types/alerts-cursor'
import {parseAlertsGroup, type AlertsGroup} from '../types/get-alerts-groups-request'

export function useAlertsParams() {
  const [params, setParams] = useSearchParams()
  const [query, setQuery] = useState<string>(() => params.get('query') || defaultQuery)
  const [cursor, setCursor] = useState<AlertsCursor | null>(() => parseAlertsCursor(params))
  const [group, setGroup] = useState<AlertsGroup>(() => parseAlertsGroup(params.get('group')))

  // Changing the query also resets the cursor.
  // Calling setParams twice in one render doesn't appear to work correctly so we need to do it in a single call.
  const onQueryChange = (newQuery: string) => {
    setQuery(newQuery)
    setCursor(null)
    setParams(prevParams => {
      const next = new URLSearchParams(prevParams)
      next.set('query', newQuery)
      next.delete('before')
      next.delete('after')
      return next
    })
  }

  const onCursorChange = (newCursor: AlertsCursor | null) => {
    setCursor(newCursor)
    setParams(prevParams => {
      const next = new URLSearchParams(prevParams)
      serializeAlertsCursor(newCursor, next)
      return next
    })
  }

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

  return {query, cursor, group, onQueryChange, onCursorChange, onGroupChange}
}

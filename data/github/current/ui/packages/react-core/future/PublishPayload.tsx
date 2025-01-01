import {useQueryClient} from '@github-ui/react-query'
import {SoftNavPayloadEvent} from '@github-ui/soft-nav/events'
import {SOFT_NAV_STATE} from '@github-ui/soft-nav/states'
import type {QueryClient} from '@tanstack/react-query'
import {useEffect} from 'react'

import {useAppPayload} from '../use-app-payload'
import {QueryRouteQueryType} from './data-router-types'
import {type RouteMatches, useRouteMatches} from './query-route'

// This exists to satisfy the eslint warning `@eslint-react/web-api/no-leaked-event-listener`
// which is triggered by it not knowing that it's a constant string literal when referenced
// as an imported thing.
const SOFT_NAV_INITIAL = SOFT_NAV_STATE.INITIAL

export function PublishPayload() {
  const appPayload = useAppPayload()

  const matches = useRouteMatches()
  const queryClient = useQueryClient()

  // Fires any time the `matches` changes, such as a soft-nav.
  // Will fire on initial hard-nav too but then the ReactStaffbarElement component
  // might not be ready, yet, to listen to the event.
  useEffect(() => {
    const payload = aggregateMatchData(matches, queryClient)
    document.dispatchEvent(new SoftNavPayloadEvent({payload, appPayload}))
  }, [matches, appPayload, queryClient])

  // Exists for the purpose of the first hard-nav, when the ReactStaffbarElement component might not
  // be ready, yet, but when it is we send the first payload.
  useEffect(() => {
    function onInitialSoftNav() {
      const payload = aggregateMatchData(matches, queryClient)
      document.dispatchEvent(new SoftNavPayloadEvent({payload, appPayload}))
    }
    document.addEventListener(SOFT_NAV_INITIAL, onInitialSoftNav)

    return () => {
      document.removeEventListener(SOFT_NAV_INITIAL, onInitialSoftNav)
    }
  }, [matches, appPayload, queryClient])

  return null
}

function aggregateMatchData(matches: RouteMatches, queryClient: QueryClient) {
  // returns a Record<RouteId, Data>
  const payload: Record<string, unknown> = {}
  for (const match of matches) {
    if (!match.data) continue
    const id = match.data.route.id
    for (const config of Object.values(match.data.queries)) {
      if (config.type === QueryRouteQueryType.Blocking) {
        payload[id] = queryClient.getQueryData(config.queryConfig.queryKey)
      }
    }
  }
  return payload
}

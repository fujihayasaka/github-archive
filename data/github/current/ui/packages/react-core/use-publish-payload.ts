import {SoftNavPayloadEvent} from '@github-ui/soft-nav/events'
import {SOFT_NAV_STATE} from '@github-ui/soft-nav/states'
import {useEffect} from 'react'

import {useAppPayload} from './use-app-payload'
import {useRoutePayload} from './use-route-payload'

export function usePublishPayload() {
  const payload = useRoutePayload()
  const appPayload = useAppPayload()

  useEffect(() => {
    function onInitialSoftNav() {
      // For a hard navigation, we publish the payload on INITIAL event
      // because the first payload changed is too early and some components (Catalyst) may not be ready yet.
      // This may trigger the same event twice.
      document.dispatchEvent(new SoftNavPayloadEvent({payload, appPayload}))
    }
    const abortController = new AbortController()
    document.addEventListener(SOFT_NAV_STATE.INITIAL, onInitialSoftNav, {signal: abortController.signal})

    return () => {
      abortController.abort()
    }
  }, [appPayload, payload])

  useEffect(() => {
    document.dispatchEvent(new SoftNavPayloadEvent({payload, appPayload}))
  }, [appPayload, payload])
}

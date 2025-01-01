import {matchRoutes, useNavigate} from 'react-router-dom'
import type {NavigatorAppRegistration} from './navigator-app-registry'
import {startTransition, useEffect} from 'react'
import {ssrSafeDocument} from '@github-ui/ssr-utils'

export const useSoftNavListener = (routes: NavigatorAppRegistration['routes']) => {
  const reactRouterNavigate = useNavigate()

  useEffect(() => {
    const onSoftNav = (e: Event) => {
      if (!(e instanceof CustomEvent)) return

      const {data, url} = e.detail
      const matchedRoutes = matchRoutes(routes, url)

      const path = `${url.pathname}${url.search}${url.hash}`

      // force hard nav
      if (!matchedRoutes) {
        window.location.href = path || window.location.href
        return
      }

      startTransition(() => {
        // HACK: Navigator will see this __prefetched_data param in history and skip data fetching, using the data
        // from this instead.
        reactRouterNavigate(path, {
          state: {
            __prefetched_data: data,
          },
        })

        const {turbo, ...state} = window.history.state ?? {}

        // We don't want the full payload in history after the navigation is done
        if (state?.usr?.__prefetched_data) delete state.usr.__prefetched_data

        window.history.replaceState({...state, skipTurbo: true}, '', location.href)
      })
    }

    const abortController = new AbortController()
    ssrSafeDocument?.addEventListener('react:soft-nav', onSoftNav, {signal: abortController.signal})

    return () => {
      // Ensure only one listener exist at a time to avoid navigating multiple times
      abortController.abort()
    }
  }, [reactRouterNavigate, routes])
}

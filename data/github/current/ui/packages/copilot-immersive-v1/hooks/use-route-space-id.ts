import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {useMemo} from 'react'

const spaceIdRegex = /\/copilot\/spaces\/([^/]+)/

/**
 * Parses the space ID from the current URL and returns it.
 * We have to rely on the URL from the browser history because the space ID in the React Router state may be stale
 * since we manually push a history entry when creating a new thread and don't perform a navigation.
 */
export function useRouteSpaceId() {
  const pathname = ssrSafeLocation.pathname
  return useMemo(() => {
    const match = pathname.match(spaceIdRegex)
    if (!match) return null

    const [, spaceId] = match
    return spaceId ?? null
  }, [pathname])
}

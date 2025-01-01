import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {useMemo} from 'react'

const threadIdRegex = /\/copilot\/c\/([^/]+)/
const sharedThreadIdRegex = /\/copilot\/share\/([^/]+)/

/**
 * Parses the thread ID from the current URL and returns it.
 * We have to rely on the URL from the browser history because the thread ID in the React Router state may be stale
 * since we manually push a history entry when creating a new thread and don't perform a navigation.
 */
export function useRouteThreadId() {
  const pathname = ssrSafeLocation.pathname
  return useMemo(() => {
    const match = pathname.match(threadIdRegex) || pathname.match(sharedThreadIdRegex)
    if (!match) return null

    const [, threadId] = match
    return threadId ?? null
  }, [pathname])
}

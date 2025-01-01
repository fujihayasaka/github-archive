import {useAlive} from '@github-ui/use-alive'
import {throttle} from '@github/mini-throttle'
import useIsMounted from '@github-ui/use-is-mounted'
import {useCallback, useMemo} from 'react'

// The event names that can be watched for in the alive message - add new events here
export const PR_ALIVE_EVENT_NAMES = [
  'git_updated',
  'title_updated',
  'body_updated',
  'timeline_updated',
  'sidebar_updated',
] as const

// Maps PR_ALIVE_EVENT_NAMES to a union of the event names
type EventNames = (typeof PR_ALIVE_EVENT_NAMES)[number]

// Strongly type the event updates that can be watched for in the alive message
type EventUpdate = {
  [key in EventNames]?: boolean
}

export function useRefetchOnAliveUpdate(channel: string, refetch: () => void, watchFor?: EventUpdate): void {
  const isMounted = useIsMounted()

  const throttledRefetch = useMemo(
    () =>
      throttle(() => {
        if (isMounted()) {
          refetch()
        }
      }, 2000),
    [isMounted, refetch],
  )

  const handleNotification = useCallback(
    (data: {wait?: number; event_updates: EventUpdate}) => {
      if (watchFor && data.event_updates) {
        const watchForEntries = Object.entries(watchFor) as Array<[EventNames, boolean]>
        for (const [key, value] of watchForEntries) {
          if (!!data.event_updates[key] === !!value) {
            window.setTimeout(throttledRefetch, data.wait || 0)
          }
        }
      } else {
        // If we're not watching for anything specific, just refetch
        window.setTimeout(throttledRefetch, data.wait || 0)
      }
    },
    [throttledRefetch, watchFor],
  )

  useAlive(channel, handleNotification)
}

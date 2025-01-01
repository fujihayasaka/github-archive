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

/**
 * Refetches data on alive updates for a given channel
 * Syntactic sugar for useRepondToAliveUpdate for consumer clarity
 */
export function useRefetchOnAliveUpdate(
  channel: string,
  refetch: () => void,
  watchFor?: EventUpdate,
  throttleTimeout?: number,
) {
  useRepondToAliveUpdate(channel, refetch, watchFor, throttleTimeout)
}

/**
 * Respond to alive updates on a given channel
 */
export function useRepondToAliveUpdate(
  channel: string,
  handler: () => void,
  watchFor?: EventUpdate,
  throttleTimeout?: number,
): void {
  const isMounted = useIsMounted()

  const throttledHandler = useMemo(
    () =>
      throttle(() => {
        if (isMounted()) {
          handler()
        }
      }, throttleTimeout ?? 2000),
    [isMounted, handler, throttleTimeout],
  )

  const handleNotification = useCallback(
    (data: {wait?: number; event_updates: EventUpdate}) => {
      if (watchFor && data.event_updates) {
        const watchForEntries = Object.entries(watchFor) as Array<[EventNames, boolean]>
        for (const [key, value] of watchForEntries) {
          if (!!data.event_updates[key] === !!value) {
            window.setTimeout(throttledHandler, data.wait || 0)
          }
        }
      } else {
        // If we're not watching for anything specific, just refetch
        window.setTimeout(throttledHandler, data.wait || 0)
      }
    },
    [throttledHandler, watchFor],
  )

  useAlive(channel, handleNotification)
}

import {useAlive} from '@github-ui/use-alive'
import {throttle} from '@github/mini-throttle'
import useIsMounted from '@github-ui/use-is-mounted'
import {useCallback, useMemo} from 'react'
import {BACKGROUND_REFETCH_THROTTLE_INTERVAL_IN_MS, FOREGROUND_REFETCH_THROTTLE_INTERVAL_IN_MS} from '../constants'

import {useStatusChecksPageData} from '../page-data/loaders/use-status-checks-page-data'
import {usePageVisibility} from './use-page-visibility'

export function useStatusChecksLiveUpdates(channel: string, pullRequestHeadSha: string): void {
  const {refetch} = useStatusChecksPageData({pullRequestHeadSha})
  const isMounted = useIsMounted()
  const isPageVisible = usePageVisibility()

  const throttleTiming = isPageVisible
    ? FOREGROUND_REFETCH_THROTTLE_INTERVAL_IN_MS
    : BACKGROUND_REFETCH_THROTTLE_INTERVAL_IN_MS

  const throttledRefetch = useMemo(
    () =>
      throttle(() => {
        if (isMounted()) {
          refetch()
        }
      }, throttleTiming),
    [isMounted, refetch, throttleTiming],
  )

  const handleNotification = useCallback(
    (data: {wait?: number}) => {
      // This creates a 2-10s throttle to prevent multiple refetches happening in the same < 500ms time window
      window.setTimeout(throttledRefetch, data.wait || 0)
    },
    [throttledRefetch],
  )

  useAlive(channel, handleNotification)
}

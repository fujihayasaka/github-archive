import {throttle} from '@github/mini-throttle'
import {useAlive} from '@github-ui/use-alive'
import useIsMounted from '@github-ui/use-is-mounted'
import {useMemo, useState, useEffect} from 'react'
import {usePageVisibility} from './use-page-visibility'

export type Channels = {
  stateChannel: string | null | undefined
  deployedChannel: string | null | undefined
  reviewStateChannel: string | null | undefined
  workflowsChannel: string | null | undefined
  mergeQueueChannel: string | null | undefined
  headRefChannel: string | null | undefined
  baseRefChannel: string | null | undefined
  gitMergeStateChannel: string | null | undefined
  pullRequestChannel: string | null | undefined
}

export function useMergeabilityLiveUpdates({
  channels,
  refetchQuery,
}: {
  channels: Channels
  refetchQuery: () => void
}): void {
  const aliveMergabilityChannels: string[] = useMemo(() => {
    return Object.values(channels).filter((channel): channel is string => channel !== null)
  }, [channels])
  const isMounted = useIsMounted()
  const [hasPendingUpdate, setHasPendingUpdate] = useState(false)
  const isPageVisible = usePageVisibility()

  // There are several PR websocket events that can trigger a refresh of the MergeBox Pull Request data.
  // This creates a 2000ms throttle to prevent multiple refetches happening in the same < 500ms time window
  // This is also in place to preventing inflicting a DDOS attack on ourselves by refetching too often.
  const throttleRefetchingPullRequestData = useMemo(
    () =>
      throttle(() => {
        if (isMounted()) {
          refetchQuery()
        }
      }, 2000),
    [refetchQuery, isMounted],
  )

  const handleMergabilityChannelNotification = useMemo(
    () => (data: {wait?: number}) => {
      if (isPageVisible) {
        // Some of our WebSocket event notifications include a wait value to assure that we consider replication lag times.
        // We need to avoid calling our refetching method until that wait time is over by using a setTimeout that is equal to the data.wait value, if it exists.
        window.setTimeout(() => throttleRefetchingPullRequestData(), data.wait || 0)
      } else {
        setHasPendingUpdate(true)
      }
    },
    [isPageVisible, throttleRefetchingPullRequestData],
  )

  useEffect(() => {
    if (isMounted() && isPageVisible && hasPendingUpdate) {
      setHasPendingUpdate(false)
      refetchQuery()
    }
  }, [isPageVisible, hasPendingUpdate, setHasPendingUpdate, isMounted, refetchQuery])

  for (const channel of aliveMergabilityChannels) {
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/rules-of-hooks
    useAlive(channel, handleMergabilityChannelNotification)
  }
}

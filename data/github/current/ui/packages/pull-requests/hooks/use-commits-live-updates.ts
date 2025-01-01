import {useRefetchOnAliveUpdate} from './use-refetch-on-alive-update'
import {useCommitsPageData} from '../page-data/loaders/use-commits-page-data'

export function useCommitsLiveUpdates(channel: string, throttleTimeout?: number): void {
  const {refetch} = useCommitsPageData()
  // The default number for the throttle timeout is 2000ms
  useRefetchOnAliveUpdate(channel, refetch, {git_updated: true}, throttleTimeout)
}

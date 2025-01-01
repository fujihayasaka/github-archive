import {noop} from '@github-ui/noop'
import {useQueryClient} from '@tanstack/react-query'
import {useCallback} from 'react'

import {useEnabledFeatures} from '../../hooks/use-enabled-features'
import {pageParamForNextPlaceholder} from '../memex-items/queries/types'
import {usePaginatedMemexItemsQuery} from '../memex-items/queries/use-paginated-memex-items-query'
import {EagerQueryInvalidationSingleton} from './eager-query-invalidation'
import {mostRecentUpdateSingleton} from './most-recent-update'
import {pendingUpdatesSingleton} from './pending-updates'

export const useHandlePaginatedDataRefresh = () => {
  const {memex_table_without_limits} = useEnabledFeatures()
  if (memex_table_without_limits) {
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/rules-of-hooks
    return useHandlePaginatedDataRefreshMWLEnabled()
  } else {
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/rules-of-hooks
    return useHandlePaginatedDataRefreshMWLDisabled()
  }
}

// eslint-disable-next-line @eslint-react/hooks-extra/no-redundant-custom-hook
const useHandlePaginatedDataRefreshMWLDisabled = () => {
  return {handleRefresh: noop, handleCancelFetchData: noop}
}

const useHandlePaginatedDataRefreshMWLEnabled = () => {
  const {memex_sync_write_to_es} = useEnabledFeatures()
  const {invalidateAllQueries, queryKeysForGroups, queryKeysForItems, queryKeysForSecondaryGroups} =
    usePaginatedMemexItemsQuery()
  const queryClient = useQueryClient()

  const handleCancelFetchData = useCallback(() => {
    for (const queryKey of queryKeysForGroups) {
      // no need to cancel placeholder queries
      if (queryKey[3] !== pageParamForNextPlaceholder) {
        queryClient.cancelQueries({queryKey})
      }
    }
    for (const queryKey of queryKeysForSecondaryGroups) {
      // no need to cancel placeholder queries
      if (queryKey[3] !== pageParamForNextPlaceholder) {
        queryClient.cancelQueries({queryKey})
      }
    }
    for (const queryKey of queryKeysForItems) {
      // no need to cancel placeholder queries
      if (queryKey[3] !== pageParamForNextPlaceholder) {
        queryClient.cancelQueries({queryKey})
      }
    }
  }, [queryKeysForGroups, queryClient, queryKeysForSecondaryGroups, queryKeysForItems])

  const handleRefresh = useCallback(
    async (timestamp?: number, requestId?: string) => {
      // if the timestamp is older than the most recent update, then refreshing the paginated data may overwrite
      // the local state with stale denormalized state, so we ignore it
      const isMostRecentUpdate =
        // the provided timestamp (from hydro) is in the precision of seconds, so we have to reduce the locally stored
        // time to that precision (flooring so denormalizations on the same second get through)
        (timestamp || Infinity) >= Math.floor(mostRecentUpdateSingleton.get() / 1000) &&
        !pendingUpdatesSingleton.hasPendingUpdates()

      // If we eagerly invalidated the query cache for this request then we don't need to do it again
      const wasPreviouslyInvalidated =
        memex_sync_write_to_es && requestId && EagerQueryInvalidationSingleton.has(requestId)

      if (isMostRecentUpdate && !wasPreviouslyInvalidated) {
        handleCancelFetchData()
        return invalidateAllQueries()
      }
    },
    [invalidateAllQueries, handleCancelFetchData, memex_sync_write_to_es],
  )

  return {handleRefresh, handleCancelFetchData}
}

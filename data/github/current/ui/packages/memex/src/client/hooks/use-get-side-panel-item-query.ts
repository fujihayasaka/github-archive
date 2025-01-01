import {noop} from '@github-ui/noop'
import {useQueryClient} from '@tanstack/react-query'
import {useCallback} from 'react'

import type {SidePanelItem} from '../api/memex-items/side-panel-item'
import {isInstanceOfMemexItemModel} from '../models/memex-item-model'
import {useSidePanelItemQuery} from '../queries/side-panel'
import {
  getInitialDataForSidePanelItem,
  setQueryDataForSidePanelItemInQueryClient,
  updateMemexItemInQueryClient,
} from '../state-providers/memex-items/query-client-api/memex-items'
import {useEnabledFeatures} from './use-enabled-features'
import type {UseSidePanelItemReturnType} from './use-side-panel-item-return-type'

export const useGetSidePanelItemQuery = (
  itemIdParam: string | number | null,
): UseSidePanelItemReturnType | undefined => {
  const queryClient = useQueryClient()
  const {memex_side_panel_query} = useEnabledFeatures()

  const setQueryDataForSidePanelItem = useCallback(
    (item: SidePanelItem) => {
      if (!(memex_side_panel_query && isInstanceOfMemexItemModel(item))) return
      setQueryDataForSidePanelItemInQueryClient(queryClient, item)
    },
    [memex_side_panel_query, queryClient],
  )
  const initialData = memex_side_panel_query ? getInitialDataForSidePanelItem(queryClient, itemIdParam) : undefined

  const query = useSidePanelItemQuery({
    variables: {itemId: itemIdParam},
    enabled: memex_side_panel_query && !!itemIdParam,
    initialData,
  })

  const setItemIsLoaded = useCallback(
    (isLoaded: boolean) => {
      if (!isLoaded) {
        query.refetch()
      }
    },
    [query],
  )

  const reloadPaneItem = useCallback(async () => {
    const result = await query.refetch()
    if (result.data) {
      updateMemexItemInQueryClient(queryClient, result.data)
    }
  }, [query, queryClient])

  return memex_side_panel_query
    ? {
        paneItem: query?.data,
        isItemLoading: query.isLoading,
        loadPaneItemData: noop, // query automatically loads item when .data is accessed
        reloadPaneItem,
        setQueryDataForSidePanelItem,
        setItemIsLoaded,
      }
    : undefined
}

import {useQueryClient} from '@tanstack/react-query'
import {useCallback, useEffect, useRef} from 'react'

import {apiGetItem} from '../api/memex-items/api-get-item'
import {ItemType} from '../api/memex-items/item-type'
import type {SidePanelItem} from '../api/memex-items/side-panel-item'
import {isInstanceOfMemexItemModel, type MemexItemModel} from '../models/memex-item-model'
import {useGetSidePanelItemNotOnClient} from '../queries/side-panel'
import {
  getQueryDataForSidePanelItemNotOnClientFromQueryClient,
  setQueryDataForSidePanelItemNotOnClientInQueryClient,
} from '../state-providers/memex-items/query-client-api/memex-items'
import {useMemexItems} from '../state-providers/memex-items/use-memex-items'
import {useSetMemexItemData} from '../state-providers/memex-items/use-set-memex-item-data'
import {useEnabledFeatures} from './use-enabled-features'
import {useGetSidePanelItemQuery} from './use-get-side-panel-item-query'
import type {UseSidePanelItemReturnType} from './use-side-panel-item-return-type'

/**
 * Wraps the useGetSidePanelItemNotOnClient query hook to only run if all of the following are true:
 * 1. The memex_table_without_limits feature is enabled
 * 2. The itemIdParam is not null
 * 3. The paneItem is undefined
 *
 * When all 3 of those are true, it means we are in a MWL project where we have a itemIdParam from the URL,
 * but we were unable to find the item in `useMemexItems` because the item is not on the client.
 *
 * If the FF is disabled, we will return undefined for the query, and a no-op for setQueryDataForSidePanelItem, to avoid running the query at all for these projects.
 * If the FF is enabled, but we don't have an itemIdParam, or we do have an itemIdParam but we were able to find the item in `useMemexItems`,
 * we will return the query, but it will be disabled, to avoid a call to the queryFn.
 */
const useGetSidePanelItemNotOnClientQuery = (itemIdParam: string | null, paneItem: MemexItemModel | undefined) => {
  const queryClient = useQueryClient()
  const {memex_table_without_limits} = useEnabledFeatures()

  const setQueryDataForSidePanelItem = useCallback(
    (item: SidePanelItem) => {
      if (!memex_table_without_limits) return
      if (!isInstanceOfMemexItemModel(item)) return
      setQueryDataForSidePanelItemNotOnClientInQueryClient(queryClient, item)
    },
    [memex_table_without_limits, queryClient],
  )
  if (!memex_table_without_limits) return {query: undefined, setQueryDataForSidePanelItem}

  const initialData = getQueryDataForSidePanelItemNotOnClientFromQueryClient(queryClient, itemIdParam)
  // eslint-disable-next-line react-compiler/react-compiler
  // eslint-disable-next-line react-hooks/rules-of-hooks
  const initialDataRef = useRef(initialData)

  // We only want to enable the query if:
  // 1. We have an item id in the URL
  // 2. We do not yet have an item for that id
  // 3. No data was manually set for this item already as initialData
  const enabled = !!(itemIdParam && !paneItem && !initialDataRef.current)
  // eslint-disable-next-line react-compiler/react-compiler
  // eslint-disable-next-line react-hooks/rules-of-hooks
  const query = useGetSidePanelItemNotOnClient({
    variables: {itemId: itemIdParam},
    enabled,
    initialData,
  })

  return {query, setQueryDataForSidePanelItem}
}

/**
 * Determine whether to reload the side panel item after a PWL live update.
 *
 * When Projects Without Limits is enabled and a live update is received,
 * the client will refresh item data in the query cache.
 * By default, the side panel would reload the side panel item from the
 * updated cache, but items in the query cache have fewer fields serialized
 * than items in the side panel.
 *
 * To provide a more stable UX, this check tells the side panel to continue
 * to display the stale item while a separate query is made to refresh
 * the side panel item with all fields serialized.
 */
function showPreviousAndReload(paneItem: MemexItemModel, previousItem: MemexItemModel): boolean {
  const sameItem = previousItem.id === paneItem.id
  return sameItem && paneItem.memexProjectColumnValues.length < previousItem.memexProjectColumnValues.length
}

const useSidePanelItemLegacy = (itemIdParam: string | null): UseSidePanelItemReturnType => {
  const {items} = useMemexItems()
  let paneItem = itemIdParam ? items.find(item => item.id === parseInt(itemIdParam)) : undefined
  const {query: sidePanelItemNotOnClientQuery, setQueryDataForSidePanelItem} = useGetSidePanelItemNotOnClientQuery(
    itemIdParam,
    paneItem,
  )

  if (!paneItem && sidePanelItemNotOnClientQuery?.data) {
    // If we have a result from the query, use that as the paneItem.
    // If the MWL FF is disabled, the query will be undefined, and we never made a request to fetch the
    // data (because the query itself was disabled), then we will use the paneItem from the URL.
    paneItem = sidePanelItemNotOnClientQuery.data
  }

  const {setItemData} = useSetMemexItemData()

  const loadPaneItemData = useCallback(
    async (item: SidePanelItem) => {
      const memexProjectItemId = item.memexItemId?.()
      /**
       * Don't try to load item data if it's not a project item
       */
      if (memexProjectItemId === undefined) return
      const res = await apiGetItem({memexProjectItemId})
      if (res.ok) {
        setItemData(res.data.memexProjectItem)
      }
    },
    [setItemData],
  )

  const {memex_table_without_limits} = useEnabledFeatures()
  const previousItemRef = useRef(paneItem)
  if (memex_table_without_limits) {
    // eslint-disable-next-line react-compiler/react-compiler
    if (paneItem && previousItemRef.current && showPreviousAndReload(paneItem, previousItemRef.current)) {
      // eslint-disable-next-line react-compiler/react-compiler
      setItemData(previousItemRef.current)
      loadPaneItemData(paneItem)
    }
    // eslint-disable-next-line react-compiler/react-compiler
    previousItemRef.current = paneItem
  }

  const reloadPaneItem = useCallback(async () => {
    if (!paneItem) return
    loadPaneItemData(paneItem)
  }, [loadPaneItemData, paneItem])

  const itemIsLoaded = useRef<boolean>(false)
  useEffect(() => {
    if (paneItem?.contentType === ItemType.DraftIssue && !itemIsLoaded.current) {
      itemIsLoaded.current = true
      loadPaneItemData(paneItem)
    }
  }, [paneItem, loadPaneItemData])

  const setItemIsLoaded = useCallback((isLoaded: boolean) => {
    itemIsLoaded.current = isLoaded
  }, [])

  return {
    paneItem,
    isItemLoading: sidePanelItemNotOnClientQuery?.isLoading || false,
    reloadPaneItem,
    setQueryDataForSidePanelItem,
    setItemIsLoaded,
    loadPaneItemData,
  }
}

export const useSidePanelItem = (itemIdParam: string | null): UseSidePanelItemReturnType => {
  const sidePanel = useGetSidePanelItemQuery(itemIdParam)
  const legacySidePanel = useSidePanelItemLegacy(itemIdParam)

  // If memex_side_panel_query is disabled, we'll fall
  // back to the legacy implementation.
  return sidePanel ? sidePanel : legacySidePanel
}

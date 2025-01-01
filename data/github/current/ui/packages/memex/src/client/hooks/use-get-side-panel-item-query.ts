import {useQueryClient} from '@tanstack/react-query'
import {useCallback} from 'react'

import type {MemexItemModel} from '../models/memex-item-model'
import {useSidePanelItemQuery} from '../queries/side-panel'
import {
  getInitialDataForSidePanelItem,
  setQueryDataForSidePanelItemInQueryClient,
  updateMemexItemInQueryClient,
} from '../state-providers/memex-items/query-client-api/memex-items'

type UseSidePanelItemReturnType = {
  paneItem: MemexItemModel | undefined
  isItemLoading: boolean
  reloadPaneItem: () => void
  setQueryDataForSidePanelItem: (item: MemexItemModel) => void
}

export const useGetSidePanelItemQuery = (itemIdParam: string | number | null): UseSidePanelItemReturnType => {
  const queryClient = useQueryClient()

  const setQueryDataForSidePanelItem = useCallback(
    (item: MemexItemModel) => {
      setQueryDataForSidePanelItemInQueryClient(queryClient, item)
    },
    [queryClient],
  )
  const initialData = getInitialDataForSidePanelItem(queryClient, itemIdParam)

  const {data, isLoading, refetch} = useSidePanelItemQuery({
    variables: {itemId: itemIdParam},
    enabled: !!itemIdParam,
    initialData,
  })

  const reloadPaneItem = useCallback(async () => {
    const result = await refetch()
    if (result.data) {
      updateMemexItemInQueryClient(queryClient, result.data)
    }
  }, [refetch, queryClient])

  return {
    paneItem: data,
    isItemLoading: isLoading,
    reloadPaneItem,
    setQueryDataForSidePanelItem,
  }
}

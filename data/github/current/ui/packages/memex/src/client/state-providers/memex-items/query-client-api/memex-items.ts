import type {Query, QueryClient, QueryFilters} from '@tanstack/react-query'

import type {IColumnWithItems} from '../../../api/columns/contracts/column-with-items'
import type {MemexColumnData} from '../../../api/columns/contracts/storage'
import type {MemexItem, UpdateMemexItemResponseData} from '../../../api/memex-items/contracts'
import {ItemType} from '../../../api/memex-items/item-type'
import type {PaginatedTotalCount} from '../../../api/memex-items/paginated-views'
import {getEnabledFeatures} from '../../../helpers/feature-flags'
import {createMemexItemModel, type MemexItemModel} from '../../../models/memex-item-model'
import {useSidePanelItemQuery} from '../../../queries/side-panel'
import {mergeItemData} from '../memex-item-helpers'
import {isPageParamsDataGrouped} from '../queries/query-data-helpers'
import {
  buildMemexGroupedItemsQueryKey,
  buildMemexUngroupedItemsQueryKey,
  buildPaginatedTotalCountsQueryKey,
  createGroupedItemsId,
  getPageTypeFromQueryKey,
  type GroupId,
  isPageTypeForGroupedItems,
  isQueryForItems,
  isQueryKeyForGroupedItems,
  type MemexGroupedItemsQueryKey,
  type PageTypeForGroupedItems,
  type PaginatedMemexItemsQueryKey,
  paginatedMemexItemsQueryKey,
} from '../queries/query-keys'
import {
  type GroupedPageParamsQueryData,
  type MemexItemsPageQueryData,
  type MemexItemsTotalCountsQueryData,
  type MemexPageQueryData,
  type PageParam,
  pageParamForInitialPage,
  type PaginatedMemexItemsQueryVariables,
} from '../queries/types'
import {createPageQueryDataFromItems, type UseMemexItemsQueryData} from '../queries/use-memex-items-query'
import type {ReorderItemData} from '../types'
import {getKey, getPaginatedQueryKeyWithVariables} from './helpers'
import {
  getQueryDataForMemexItemsTotalCounts,
  incrementMemexItemsTotalCount,
  incrementMemexItemsTotalCountForGroup,
  mergeQueryDataForMemexItemsTotalCounts,
} from './memex-totals'
import {getPageParamsQueryDataForVariables, setPageParamsQueryDataForVariables} from './page-params'

export type OptimisticUpdateRollbackData = {
  queryData: Array<{queryKey: PaginatedMemexItemsQueryKey; queryData: MemexItemsPageQueryData}>
  totalCounts: MemexItemsTotalCountsQueryData
}

/**
 * Returns false if `memex_table_without_limits` is enabled
 */
function shouldUseSinglePageQuery() {
  const {memex_table_without_limits} = getEnabledFeatures()
  return !memex_table_without_limits
}

function getItemsForActiveQueries(queryClient: QueryClient) {
  const baseKey = getKey(queryClient)
  const queriesData = queryClient.getQueriesData<MemexPageQueryData>({queryKey: baseKey})
  // The result of `getQueriesData` is an array of arrays, where the first element is the query key,
  // and the second element is the query data. We want to flatten this into a single array of query data.
  return queriesData.flatMap(q => (q[1] && 'nodes' in q[1] ? q[1]?.nodes : []))
}

function getActiveMemexItemsQueryVariables(queryClient: QueryClient): PaginatedMemexItemsQueryVariables {
  const keyWithVariables = getPaginatedQueryKeyWithVariables(queryClient)
  return keyWithVariables[2] as PaginatedMemexItemsQueryVariables
}

function getQueryKeyForItem(queryClient: QueryClient, id: number): PaginatedMemexItemsQueryKey | undefined {
  const queriesData = queryClient.getQueriesData<MemexPageQueryData>(activeMemexItemsQueryFilter)
  for (const [queryKey, queryData] of queriesData) {
    if (queryData && 'nodes' in queryData && queryData.nodes.find(item => item.id === id)) {
      return queryKey as PaginatedMemexItemsQueryKey
    }
  }
  return undefined
}

function getQueryKeyForFirstPageOfGroup(queryClient: QueryClient, newPageType: PageTypeForGroupedItems) {
  const keyWithVariables = getPaginatedQueryKeyWithVariables(queryClient)
  return [...keyWithVariables, newPageType, pageParamForInitialPage] as MemexGroupedItemsQueryKey
}

function createQueryDataFromItems(items: Array<MemexItemModel>): UseMemexItemsQueryData {
  return {
    pages: [createPageQueryDataFromItems(items)],
    pageParams: [],
  }
}

function isQueryPageOfItems(queryData: MemexPageQueryData | undefined): queryData is MemexItemsPageQueryData {
  return queryData !== undefined && 'nodes' in queryData
}

/**
 * Updates the local state of a MemexItemModel with new values from the server
 * if the item is visible in the side panel.
 * A new MemexItemModel is created to replace the existing item in our client-side state,
 * so that a re-render is triggered.
 * @param queryClient
 * @param newMemexItem New data that we're looking to merge values into an existingMemexItemModel in our client state
 */
function updateSidePanelItemInQueryClient(
  queryClient: QueryClient,
  newMemexItem: MemexItem | UpdateMemexItemResponseData,
) {
  const sidePanelItem = getQueryDataForSidePanelItemFromQueryClient(queryClient, newMemexItem.id.toString())
  if (sidePanelItem) {
    const mergedItem = mergeItemData(sidePanelItem, newMemexItem)
    if (mergedItem) {
      const memexItemModel = createMemexItemModel(mergedItem)
      setQueryDataForSidePanelItemInQueryClient(queryClient, memexItemModel)
    }
  }
}

// This is the query filter that we use to get the active queries for the memex items query - it can be passed
// to `setQueryData` to update the active queries for the memex items query.
// We include a `predicate` to filter out queries indirectly related to items/groups data, such as
// page params, slice by data, total counts, etc.
const activeMemexItemsQueryFilter: QueryFilters<MemexPageQueryData, Error, MemexPageQueryData> = {
  queryKey: ['memex', paginatedMemexItemsQueryKey],
  exact: false,
  type: 'active',
  predicate: (query: Query<MemexPageQueryData, Error, MemexPageQueryData>) => {
    return isQueryForItems(query as Query<unknown, Error, unknown>)
  },
}

/**
 * A thin wrapper around getQueryData for getting the memex items data for a single page/query.
 * @param queryClient
 * @param variables PaginatedMemexItemsQueryVariables used in the query key
 * @param pageParam Page param for the data we're getting to be included in the query key
 */
export function getQueryDataForMemexItemsPage(
  queryClient: QueryClient,
  variables: PaginatedMemexItemsQueryVariables,
  pageParam: PageParam,
): MemexItemsPageQueryData | undefined {
  const queryKey = buildMemexUngroupedItemsQueryKey(variables, pageParam)
  return queryClient.getQueryData<MemexItemsPageQueryData>(queryKey)
}

/**
 * A thin wrapper around getQueryData for getting the memex items data for a single page/query of grouped items.
 * @param queryClient
 * @param variables PaginatedMemexItemsQueryVariables used in the query key
 * @param pageParam Page param for the data we're getting to be included in the query key
 * @param pageType Page type with a group id of the data we're getting to be included in the query key
 */
export function getQueryDataForGroupedItemsPage(
  queryClient: QueryClient,
  variables: PaginatedMemexItemsQueryVariables,
  pageType: PageTypeForGroupedItems,
  pageParam: PageParam,
): MemexItemsPageQueryData | undefined {
  const queryKey = buildMemexGroupedItemsQueryKey(variables, pageType, pageParam)
  return queryClient.getQueryData<MemexItemsPageQueryData>(queryKey)
}

/**
 * A thin wrapper around setQueryData for setting the memex items data for a single page/query.
 * @param queryClient
 * @param variables PaginatedMemexItemsQueryVariables used in the query key
 * @param pageParam Page param for the data we're setting to be included in the query key
 * @param queryData The new items data
 */
export function setQueryDataForMemexItemsPage(
  queryClient: QueryClient,
  variables: PaginatedMemexItemsQueryVariables,
  pageParam: PageParam,
  queryData: MemexItemsPageQueryData,
) {
  const queryKey = buildMemexUngroupedItemsQueryKey(variables, pageParam)
  queryClient.setQueryData<MemexItemsPageQueryData>(queryKey, queryData)
}

/**
 * A thin wrapper around setQueryData for setting the memex items data for a single page/query of grouped items.
 * @param queryClient
 * @param variables PaginatedMemexItemsQueryVariables used in the query key
 * @param pageParam Page param for the data we're setting to be included in the query key
 * @param pageType Page type which contains the group id of the data we're setting to be included in the query key
 * @param queryData The new items data
 */
export function setQueryDataForGroupedItemsPage(
  queryClient: QueryClient,
  variables: PaginatedMemexItemsQueryVariables,
  pageType: PageTypeForGroupedItems,
  pageParam: PageParam,
  queryData: MemexItemsPageQueryData,
) {
  const queryKey = buildMemexGroupedItemsQueryKey(variables, pageType, pageParam)
  queryClient.setQueryData<MemexItemsPageQueryData>(queryKey, queryData)
}

/**
 * A thin wrapper around `getQueryData`, that returns the current list of items from the QueryClient.
 * Helpful when we want to access the current state in a callback, but not trigger a re-render, for example
 * if we need to rollback in an error case after an optimistic update.
 * @param queryClient
 * @returns List of MemexItemModels representing the current state
 */
export function getMemexItemModelsFromQueryClient(queryClient: QueryClient) {
  if (shouldUseSinglePageQuery()) {
    const queryData = queryClient.getQueryData<UseMemexItemsQueryData>(getKey(queryClient))
    return getItemsFromQueryData(queryData) || []
  } else {
    return getItemsForActiveQueries(queryClient)
  }
}

/**
 * A thin wrapper around `getQueryData`, with type safety for the correct key.
 * This method is mainly exposed for use cases where we want to access the query data
 * holistically, like adding to a mutation context to support a rollback.
 * In general, if we're accessing items or page data, we should prefer a different helper.
 * @param queryClient
 * @returns query data for the `memexItems` key
 */
export function getMemexItemsQueryDataFromQueryClient(queryClient: QueryClient) {
  return queryClient.getQueryData<UseMemexItemsQueryData>(getKey(queryClient))
}

/**
 * A thin wrapper around `setQueryData`, with type safety for the correct key.
 * This method is mainly exposed for use cases where we want to set the query data
 * holistically, if we have accessed a mutation's context and need to rollback the entire mutation.
 * In general, if we're mutating items or page data, we should prefer a different helper.
 * @param queryClient
 * @param queryData data to set in the query client for the `memexItems` key
 */
export function setMemexItemsQueryDataInQueryClient(queryClient: QueryClient, queryData: UseMemexItemsQueryData) {
  queryClient.setQueryData<UseMemexItemsQueryData>(getKey(queryClient), {...queryData})
}

/**
 * As long as structuralSharing is disabled for the query, this method will
 * force a re-render by creating an array with a new identity, but re-using our
 * existing memex item models. This is needed because our MemexItemModels are
 * mutable, so when we change a column value, nothing else will force
 * a re-render.
 *
 * If we get to a point where MemexItemModels are immutable, we should be able
 * to do away with this function.
 * @param queryClient
 */
export function setMemexItemsToForceRerenderInQueryClient(queryClient: QueryClient) {
  if (shouldUseSinglePageQuery()) {
    queryClient.setQueryData<UseMemexItemsQueryData>(getKey(queryClient), queryData => {
      const oldMemexItemModels = getItemsFromQueryData(queryData)
      return createQueryDataFromItems([...(oldMemexItemModels || [])])
    })
  } else {
    queryClient.setQueriesData<MemexPageQueryData>(activeMemexItemsQueryFilter, queryData => {
      if (!isQueryPageOfItems(queryData)) {
        return queryData
      }

      return {...queryData}
    })
  }
}

/**
 * Checks the queryClient's query data to see if we have data for any query key with the `paginatedMemexItems` primaryKey.
 * For example, if we have data for a key like `['memexItems', {q: "is:draft"}]`,
 * even if the active query key is `['memexItems', {q: "is:pr"}]`.
 * This can be used to avoid passing `initialData` in `useMemexItemsPageParams`,
 * and ensure we fetch new data from the server instead.
 * @param queryClient
 * @returns Whether or not query data for any memex items related query key has been initialized
 */
export function hasMemexItemsQueryData(queryClient: QueryClient) {
  return queryClient.getQueriesData({queryKey: ['memex', paginatedMemexItemsQueryKey]}).length !== 0
}

/**
 * Looks up a MemexItemModel by its id. If no item is found, undefined is returned
 * @param queryClient
 * @param id MemexItem id
 * @returns A MemexItemModel, or undefined if the item with this id does not exist
 */
export function findMemexItemByIdInQueryClient(queryClient: QueryClient, id: number) {
  if (shouldUseSinglePageQuery()) {
    const queryData = queryClient.getQueryData<UseMemexItemsQueryData>(getKey(queryClient))
    const memexItemModels = getItemsFromQueryData(queryData)
    if (memexItemModels) {
      return memexItemModels.find((item: MemexItemModel) => item.id === id)
    }
    return undefined
  } else {
    return getItemsForActiveQueries(queryClient).find((item: MemexItemModel) => item.id === id)
  }
}

/**
 * Looks up a MemexItemModel by its id and current group id. If no item is found, false is returned, otherwise true.
 * @param queryClient
 * @param itemId MemexItem id
 * @param groupId the group id where the MemexItemModel is believed to be in
 * @returns {boolean} whether or not we found an item with the id in this group
 */
export function isMemexItemInGroup(queryClient: QueryClient, itemId: number, groupId: string) {
  const queryKeyForItem = getQueryKeyForItem(queryClient, itemId)
  if (!queryKeyForItem) return false

  const pageType = getPageTypeFromQueryKey(queryKeyForItem)
  return isPageTypeForGroupedItems(pageType) && pageType.groupId === groupId
}

/**
 * Looks up the index of a MemexItemModel by its id. If no item is found, -1 is returned.
 * If there are multiple pages of data, then the index will be the global index across all pages,
 * not within a single page of data.
 * @param queryClient
 * @param id MemexItem id
 * @returns The index of the item with provided id, or -1 if it does not exist
 */
export function findMemexItemGlobalIndexByIdInQueryClient(queryClient: QueryClient, id: number) {
  if (shouldUseSinglePageQuery()) {
    const queryData = queryClient.getQueryData<UseMemexItemsQueryData>(getKey(queryClient))
    const memexItemModels = getItemsFromQueryData(queryData)
    if (memexItemModels) {
      return memexItemModels.findIndex((item: MemexItemModel) => item.id === id)
    }
    return -1
  } else {
    return getItemsForActiveQueries(queryClient).findIndex((item: MemexItemModel) => item.id === id)
  }
}

/**
 * Adds a MemexItemModel to our client-side state. Does nothing if item with id already exists.
 * Will insert item at index provided, or push at the end of the array if none provided.
 * Triggers a re-render by using a new array object for the updated list of items.
 * @param queryClient
 * @param newMemexItemModel Item to add to the query client
 * @param index An optional index to insert the item at in the array. If omitted, will add to the end of the array.
 */
export function addMemexItemToQueryClient(queryClient: QueryClient, newMemexItemModel: MemexItemModel, index?: number) {
  if (shouldUseSinglePageQuery()) {
    const foundIndex = findMemexItemGlobalIndexByIdInQueryClient(queryClient, newMemexItemModel.id)

    queryClient.setQueryData<UseMemexItemsQueryData>(getKey(queryClient), queryData => {
      const oldMemexItemModels = getItemsFromQueryData(queryData)
      const newMemexItemModels = [...(oldMemexItemModels || [])]
      let insertIndex = index ?? newMemexItemModels.length

      if (foundIndex !== -1) {
        newMemexItemModels.splice(foundIndex, 1)
        insertIndex = foundIndex
      }

      newMemexItemModels.splice(insertIndex, 0, newMemexItemModel)
      return createQueryDataFromItems(newMemexItemModels)
    })
  } else {
    const foundIndex = findMemexItemGlobalIndexByIdInQueryClient(queryClient, newMemexItemModel.id)

    let itemAdded = false
    let globalIndex = 0

    const totalItems = getMemexItemModelsFromQueryClient(queryClient).length

    queryClient.setQueriesData<MemexPageQueryData>(activeMemexItemsQueryFilter, queryData => {
      if (!isQueryPageOfItems(queryData)) {
        return queryData
      }

      if (foundIndex !== -1) {
        // Do nothing if this item is already in the query data
        //
        // NOTE: In other cases a new object is returned, so even though we aren't changing
        // anything in the data here, return a new object to match the previous behavior.
        return {...queryData}
      }

      if (itemAdded) {
        return queryData
      }

      if (index != null && index >= globalIndex && index < globalIndex + queryData.nodes.length) {
        const newPageNodes = [...queryData.nodes]
        const indexOnPage = index - globalIndex
        newPageNodes.splice(indexOnPage, 0, newMemexItemModel)
        itemAdded = true
        return {
          ...queryData,
          nodes: newPageNodes,
        }
      } else if (index == null && globalIndex + queryData.nodes.length === totalItems) {
        itemAdded = true
        if (queryData.pageInfo.hasNextPage) {
          // We don't want to optimistically update the addition of the item
          // if we are not on the last page of all of the data - this will be incorrect.
          return queryData
        }
        // If no index was provided, we want to insert the item at the end of the last page
        const newPageNodes = [...queryData.nodes]
        newPageNodes.push(newMemexItemModel)
        return {
          ...queryData,
          nodes: newPageNodes,
        }
      } else {
        globalIndex += queryData.nodes.length
        return queryData
      }
    })

    if (itemAdded) {
      const variables = getActiveMemexItemsQueryVariables(queryClient)
      const totalCount = incrementMemexItemsTotalCount(queryClient, variables, 1)
      mergeQueryDataForMemexItemsTotalCounts(queryClient, variables, {totalCount})
    }
  }
}

/**
 * Adds a memex item to the client-side cache, based on a group that it belongs in.
 * This method does not allow for a specific index to be used, instead it will add the item
 * to the end of a group (i.e. the last page of the group), unless more data exists for the group,
 * on the server. In that scenario, we won't perform an optimistic update at all, because we would
 * be adding the item to the wrong page.
 * @param queryClient
 * @param newMemexItemModel
 * @param pageType
 * @returns
 */
export function addMemexItemForGroupToQueryClient(
  queryClient: QueryClient,
  newMemexItemModel: MemexItemModel,
  pageType: PageTypeForGroupedItems,
): boolean | undefined {
  const variables = getActiveMemexItemsQueryVariables(queryClient)
  const pageParamsQueryData = getPageParamsQueryDataForVariables(queryClient, variables)
  if (!isPageParamsDataGrouped(pageParamsQueryData)) {
    // We should never hit this, because if we're passing a `PageTypeForGroupedItems` then we should have grouped page params
    return
  }

  const groupedItemsId = createGroupedItemsId(pageType)

  // If we're unable to find page params for this groupedItemsId, it is because there aren't any items
  // yet and the server returns `groupedItems` sparsely. We will end up creating
  // an entry in the page params for this groupedItemsId as part of this process.
  // By including just the pageParamForInitialPage, we'll form the query key properly.
  const pageParamsForGroupId = pageParamsQueryData.groupedItems[groupedItemsId] || [pageParamForInitialPage]

  const lastPageParam = pageParamsForGroupId[pageParamsForGroupId.length - 1]

  const queryDataForLastPage = getQueryDataForGroupedItemsPage(queryClient, variables, pageType, lastPageParam)

  if (findMemexItemByIdInQueryClient(queryClient, newMemexItemModel.id)) {
    // Trigger an optimistic update to remove and existing item from the view
    removeMemexItemsFromQueryClient(queryClient, [newMemexItemModel.id])
  }

  const newTotalCounts = {
    totalCount: incrementMemexItemsTotalCount(queryClient, variables, 1),
    groups: {
      [pageType.groupId]: incrementMemexItemsTotalCountForGroup(queryClient, variables, pageType.groupId, 1),
    },
  }
  if (pageType.secondaryGroupId) {
    newTotalCounts.groups[pageType.secondaryGroupId] = incrementMemexItemsTotalCountForGroup(
      queryClient,
      variables,
      pageType.secondaryGroupId,
      1,
    )
  }

  if (queryDataForLastPage?.pageInfo.hasNextPage) {
    // If the last page of data for the group indicates that we have more data on the server, then we'll do nothing
    // as the optimistic update that we would make would be incorrect.
    mergeQueryDataForMemexItemsTotalCounts(queryClient, variables, newTotalCounts)
    return true
  }

  // Go ahead and add the item to the end of our last page of data for the group.
  const queryKey = buildMemexGroupedItemsQueryKey(variables, pageType, lastPageParam)

  if (queryDataForLastPage) {
    const newItemModels = [...queryDataForLastPage.nodes, newMemexItemModel]
    const newQueryData = {
      ...queryDataForLastPage,
      nodes: newItemModels,
    }

    queryClient.setQueryData<MemexPageQueryData>(queryKey, newQueryData)
  } else {
    // Getting here means that we're adding to an empty cell, so we know that the
    // new query data's nodes are just the item being added, and we don't have to worry
    // about pageInfo.
    queryClient.setQueryData<MemexPageQueryData>(queryKey, {
      nodes: [newMemexItemModel],
      pageInfo: {hasNextPage: false, hasPreviousPage: false},
    })

    // We will also have to update the page params, so that the query gets tracked.
    const newPageParams: GroupedPageParamsQueryData = {
      ...pageParamsQueryData,
      groupedItems: {...pageParamsQueryData.groupedItems, [groupedItemsId]: [pageParamForInitialPage]},
    }
    setPageParamsQueryDataForVariables(queryClient, variables, newPageParams)
  }

  mergeQueryDataForMemexItemsTotalCounts(queryClient, variables, newTotalCounts)
}

/**
 * Removes memex items matching ids provided from the client-side state.
 * Triggers a re-render by using a new array object for the updated list of items.
 * @param queryClient
 * @param ids List of ids matching items that should be removed.
 */
export function removeMemexItemsFromQueryClient(
  queryClient: QueryClient,
  ids: Array<number>,
): void | OptimisticUpdateRollbackData {
  if (shouldUseSinglePageQuery()) {
    queryClient.setQueryData<UseMemexItemsQueryData>(getKey(queryClient), queryData => {
      const oldMemexItemModels = getItemsFromQueryData(queryData) || []
      const idsSet = new Set(ids)
      const newItemModels = oldMemexItemModels.filter(item => !idsSet.has(item.id))
      return createQueryDataFromItems(newItemModels)
    })
  } else {
    const variables = getActiveMemexItemsQueryVariables(queryClient)
    const originalTotalCounts = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
    const rollbackData: OptimisticUpdateRollbackData = {queryData: [], totalCounts: originalTotalCounts}
    const idsToRemove = new Set(ids)
    let itemsRemoved = 0
    const itemCountRemovedInGroups: {[key: string]: number} = {}

    const activeQueryKeys = queryClient
      .getQueriesData<MemexPageQueryData>(activeMemexItemsQueryFilter)
      .map(([key]) => key) as Array<PaginatedMemexItemsQueryKey>

    for (const queryKey of activeQueryKeys) {
      queryClient.setQueryData<MemexPageQueryData>(queryKey, queryData => {
        if (!isQueryPageOfItems(queryData)) {
          return queryData
        }

        let rollbackDataAddedForQueryKey = false

        // don't loop through every item on the page if we've already removed all the items we intend to
        if (itemsRemoved === idsToRemove.size) return queryData

        const newPageNodes = []
        for (const itemModel of queryData.nodes) {
          if (idsToRemove.has(itemModel.id)) {
            itemsRemoved++
            const pageType = getPageTypeFromQueryKey(queryKey)
            if (isPageTypeForGroupedItems(pageType)) {
              itemCountRemovedInGroups[pageType.groupId] = (itemCountRemovedInGroups[pageType.groupId] ?? 0) + 1
              if (pageType.secondaryGroupId) {
                itemCountRemovedInGroups[pageType.secondaryGroupId] =
                  (itemCountRemovedInGroups[pageType.secondaryGroupId] ?? 0) + 1
              }
            }
            if (!rollbackDataAddedForQueryKey) {
              rollbackData.queryData.push({queryKey, queryData})
              rollbackDataAddedForQueryKey = true
            }
          } else {
            newPageNodes.push(itemModel)
          }
        }
        return {...queryData, nodes: newPageNodes}
      })
    }

    const newTotalCounts = {
      groups: Object.keys(itemCountRemovedInGroups).reduce(
        (memo, groupId) => {
          const groupItemsRemoved = itemCountRemovedInGroups[groupId] ?? 0
          memo[groupId] = incrementMemexItemsTotalCountForGroup(queryClient, variables, groupId, -groupItemsRemoved)
          return memo
        },
        {} as {[key: string]: PaginatedTotalCount},
      ),
      totalCount: incrementMemexItemsTotalCount(queryClient, variables, -itemsRemoved),
    }
    mergeQueryDataForMemexItemsTotalCounts(queryClient, variables, newTotalCounts)

    return rollbackData
  }
}

/**
 * Iterates over the data included in rollbackData param and calls setQueryData for each
 * key / queryData pair
 */
export function rollbackMemexItemData(
  queryClient: QueryClient,
  rollbackData: OptimisticUpdateRollbackData | undefined,
) {
  if (!rollbackData) {
    return
  }
  for (const {queryKey, queryData} of rollbackData.queryData) {
    queryClient.setQueryData<MemexItemsPageQueryData>(queryKey, queryData)
  }
  const variables = getActiveMemexItemsQueryVariables(queryClient)
  const totalCountsQueryKey = buildPaginatedTotalCountsQueryKey(variables)
  queryClient.setQueryData<MemexItemsTotalCountsQueryData>(totalCountsQueryKey, rollbackData.totalCounts)
}

/**
 * For a the memex items provided, update their group by moving them out of their existing query,
 * and into a query for the new group. We don't try to position the items within the new group, and
 * instead just add to the top of the first page of data for the relevant group/secondary group.
 */
export function updateGroupForMemexItems(
  queryClient: QueryClient,
  itemsToMove: Array<MemexItemModel>,
  newGroupId: GroupId,
  newSecondaryGroupId?: GroupId,
) {
  const variables = getActiveMemexItemsQueryVariables(queryClient)
  const pageParamsQueryData = getPageParamsQueryDataForVariables(queryClient, variables)
  if (!isPageParamsDataGrouped(pageParamsQueryData)) {
    // We should never hit this, because if we're passing a `PageTypeForGroupedItems` then we should have grouped page params
    return
  }

  const queryKeysToItemsMap = new Map<PaginatedMemexItemsQueryKey, Set<MemexItemModel>>()
  // Build map of query key with the items to remove from that query
  for (const item of itemsToMove) {
    const queryKeyForItem = getQueryKeyForItem(queryClient, item.id)
    if (queryKeyForItem) {
      const itemsForQueryKey = queryKeysToItemsMap.get(queryKeyForItem)
      if (itemsForQueryKey) {
        itemsForQueryKey.add(item)
      } else {
        queryKeysToItemsMap.set(queryKeyForItem, new Set([item]))
      }
    }
  }

  // Determine query key of query to move items to. We can't reliably predict the final order,
  // so we'll just place them somewhere and then rely on a live update to get the final positioning.
  const groupId = newGroupId
  const secondaryGroupId = newSecondaryGroupId
  const pageType = {groupId, secondaryGroupId}
  const queryKeyToAddItemsTo = getQueryKeyForFirstPageOfGroup(queryClient, pageType)

  const originalTotalCounts = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
  const rollbackData: OptimisticUpdateRollbackData = {queryData: [], totalCounts: originalTotalCounts}
  // We'll use this to keep track of the changes to total count values for the different
  // groups as we iterate over affected query keys.
  const totalCountIncrements: {[groupId: GroupId]: number} = {}

  // Iterate over query keys and remove items from those queries
  for (const [queryKeyToRemoveFrom, itemsToRemove] of queryKeysToItemsMap.entries()) {
    queryClient.setQueryData<MemexPageQueryData>(queryKeyToRemoveFrom, queryData => {
      if (!isQueryPageOfItems(queryData)) {
        return queryData
      }

      rollbackData.queryData.push({queryData, queryKey: queryKeyToRemoveFrom})
      const oldItemModels = queryData.nodes
      // Exclude any items that match the item ids to remove for this query
      const newItemModels = oldItemModels.filter(i => !itemsToRemove.has(i))

      return {
        ...queryData,
        nodes: newItemModels,
      }
    })

    if (isQueryKeyForGroupedItems(queryKeyToRemoveFrom)) {
      // If we're removing items from a grouped items query, we'll need to decrement the total count for the group
      const groupIdToDecrement = queryKeyToRemoveFrom[3].groupId
      if (totalCountIncrements[groupIdToDecrement]) {
        totalCountIncrements[groupIdToDecrement] -= itemsToRemove.size
      } else {
        totalCountIncrements[groupIdToDecrement] = -itemsToRemove.size
      }

      const secondaryGroupIdToDecrement = queryKeyToRemoveFrom[3].secondaryGroupId
      if (secondaryGroupIdToDecrement) {
        // If the query key has a secondary group id, we need to decrement the total count for that group as well
        if (totalCountIncrements[secondaryGroupIdToDecrement]) {
          totalCountIncrements[secondaryGroupIdToDecrement] -= itemsToRemove.size
        } else {
          totalCountIncrements[secondaryGroupIdToDecrement] = -itemsToRemove.size
        }
      }
    }
  }

  // Check to see if the target query for the move is empty.
  // If there is data, we can continue as normal.
  if (queryClient.getQueryData(queryKeyToAddItemsTo)) {
    // Insert items to beginning of query
    queryClient.setQueryData<MemexPageQueryData>(queryKeyToAddItemsTo, queryData => {
      if (!isQueryPageOfItems(queryData)) {
        return queryData
      }

      rollbackData.queryData.push({queryData, queryKey: queryKeyToAddItemsTo})
      const oldItemModels = queryData.nodes
      // Insert all of the items to move
      const newItemModels = [...itemsToMove, ...oldItemModels]

      return {
        ...queryData,
        nodes: newItemModels,
      }
    })
  } else {
    // If there isn't a query for our target query key, we'll need to set up the
    // query, by updating the page params in addition to the items query data.

    queryClient.setQueryData<MemexPageQueryData>(queryKeyToAddItemsTo, {
      nodes: itemsToMove,
      pageInfo: {hasNextPage: false, hasPreviousPage: false},
    })

    const groupedItemsId = createGroupedItemsId(pageType)

    // We will also have to update the page params, so that the query gets tracked.
    const newPageParams: GroupedPageParamsQueryData = {
      ...pageParamsQueryData,
      groupedItems: {...pageParamsQueryData.groupedItems, [groupedItemsId]: [pageParamForInitialPage]},
    }
    setPageParamsQueryDataForVariables(queryClient, variables, newPageParams)

    rollbackData.queryData.push({
      queryKey: queryKeyToAddItemsTo,
      queryData: {
        nodes: [],
        pageInfo: {hasNextPage: false, hasPreviousPage: false},
      },
    })
  }

  // Now we need to track the changes to the total counts for the target group and secondary group
  if (totalCountIncrements[groupId]) {
    totalCountIncrements[groupId] += itemsToMove.length
  } else {
    totalCountIncrements[groupId] = itemsToMove.length
  }

  if (secondaryGroupId) {
    if (totalCountIncrements[secondaryGroupId]) {
      totalCountIncrements[secondaryGroupId] += itemsToMove.length
    } else {
      totalCountIncrements[secondaryGroupId] = itemsToMove.length
    }
  }

  const newTotalCounts: Omit<MemexItemsTotalCountsQueryData, 'totalCount'> = {
    groups: {},
  }

  // Finally we iterate over the total count increments we've gathered up
  // and increment the total counts for the groups that have been affected based on the
  // existing total counts.
  for (const [groupIdToIncrement, increment] of Object.entries(totalCountIncrements)) {
    newTotalCounts.groups[groupIdToIncrement] = incrementMemexItemsTotalCountForGroup(
      queryClient,
      variables,
      groupIdToIncrement,
      increment,
    )
  }
  // Then we can merge these new total counts into the existing total counts.
  mergeQueryDataForMemexItemsTotalCounts(queryClient, variables, newTotalCounts)

  return rollbackData
}

/**
 * An implementation optimistically reordering a memex item that does not assume
 * that all items are in the same query. This implementation is used when the MWL
 * FF is enabled.
 * @param queryClient
 * @param movingItemId The id of the item that we're moving
 * @param reorderItemData Metadata about where we're moving the item to.
 * @returns {previousItemId: number | ''} | void: The id of the item that the moving item should be placed after
 * or void if we made no changes
 */
export function updateMemexItemPositionInQueryClient(
  queryClient: QueryClient,
  movingItemId: number,
  reorderItemData: ReorderItemData,
): {previousItemId: number | '' | undefined; rollbackData: OptimisticUpdateRollbackData} | void {
  const variables = getActiveMemexItemsQueryVariables(queryClient)
  const originalTotalCounts = getQueryDataForMemexItemsTotalCounts(queryClient, variables)
  const rollbackData: OptimisticUpdateRollbackData = {queryData: [], totalCounts: originalTotalCounts}
  // Find the query for the item that is being moved and remove it from the old query
  const queryKeyToRemoveFrom = getQueryKeyForItem(queryClient, movingItemId)
  // If we don't have an `overItemId` in the `reorderItemData`, then we have an `overGroupId`
  // (and possibly an `overSecondaryGroupId`) and we must be adding to an empty group,
  // so get the first (empty) page of the group
  const queryKeyToAddTo =
    'overItemId' in reorderItemData
      ? getQueryKeyForItem(queryClient, reorderItemData.overItemId)
      : getQueryKeyForFirstPageOfGroup(queryClient, {
          groupId: reorderItemData.overGroupId,
          secondaryGroupId: reorderItemData.overSecondaryGroupId,
        })

  if (!queryKeyToAddTo || !queryKeyToRemoveFrom) {
    return
  }

  let itemToMove: MemexItemModel | undefined = undefined
  let previousItemId: number | '' = ''

  queryClient.setQueryData<MemexPageQueryData>(queryKeyToRemoveFrom, queryData => {
    if (!isQueryPageOfItems(queryData)) {
      return queryData
    }

    rollbackData.queryData.push({queryKey: queryKeyToRemoveFrom, queryData})

    const oldItemModels = queryData.nodes
    const itemIndex = oldItemModels.findIndex(item => item.id === movingItemId)
    // Go ahead and save off the item that we're moving so that we don't
    // have to look it up again later
    itemToMove = oldItemModels[itemIndex]
    const newItemModels = [...oldItemModels]
    // Remove the item from its current position
    newItemModels.splice(itemIndex, 1)
    return {
      ...queryData,
      nodes: newItemModels,
    }
  })

  queryClient.setQueryData<MemexPageQueryData>(queryKeyToAddTo, queryData => {
    // If we weren't able to find an item to remove previously, just return the query data
    // without any changes
    if (!itemToMove) {
      return queryData
    }

    if (!queryData && 'overGroupId' in reorderItemData) {
      // If we don't have any query key for this query key, it means
      // we are trying to move into an empty group / cell that we
      // don't have a query for yet.

      const oldPageParams = getPageParamsQueryDataForVariables(queryClient, variables)
      const pageTypeFromQueryKey = getPageTypeFromQueryKey(queryKeyToAddTo)

      if (isPageParamsDataGrouped(oldPageParams) && isPageTypeForGroupedItems(pageTypeFromQueryKey)) {
        const groupedItemsId = createGroupedItemsId(pageTypeFromQueryKey)
        const newPageParams: GroupedPageParamsQueryData = {
          ...oldPageParams,
          groupedItems: {...oldPageParams.groupedItems, [groupedItemsId]: [pageParamForInitialPage]},
        }
        // We need to track the query that we're adding new data for.
        setPageParamsQueryDataForVariables(queryClient, variables, newPageParams)

        // If we're adding / removing from the same query, we don't want to add to the
        // rollback data twice
        if (queryKeyToAddTo !== queryKeyToRemoveFrom) {
          rollbackData.queryData.push({
            queryKey: queryKeyToAddTo,
            // The rollback data should be an empty list of items.
            queryData: {nodes: [], pageInfo: {hasNextPage: false, hasPreviousPage: false}},
          })
        }

        return {
          nodes: [itemToMove],
          pageInfo: {hasNextPage: false, hasPreviousPage: false},
        }
      }
    }

    if (!isQueryPageOfItems(queryData)) {
      return queryData
    }

    // If we're adding / removing from the same query, we don't want to add to the
    // rollback data twice
    if (queryKeyToAddTo !== queryKeyToRemoveFrom) {
      rollbackData.queryData.push({queryKey: queryKeyToAddTo, queryData})
    }

    if ('overGroupId' in reorderItemData) {
      // we don't know anything about where within the group to add
      // the item, so just add it to the end.
      // Currently this should only be used for an empty group
      return {
        ...queryData,
        nodes: [...queryData.nodes, itemToMove],
      }
    }

    const {overItemId, side} = reorderItemData

    const oldItemModels = queryData.nodes
    const itemIndex = oldItemModels.findIndex(item => item.id === overItemId)
    const newItemIndex = side === 'before' ? itemIndex : itemIndex + 1
    if (newItemIndex > 0) {
      const previousItem = oldItemModels[newItemIndex - 1]
      if (previousItem) previousItemId = previousItem.id
    } else {
      previousItemId = ''
    }
    const newItemModels = [...oldItemModels]

    // Add the item that has already been removed to its new position
    newItemModels.splice(newItemIndex, 0, itemToMove)
    return {
      ...queryData,
      nodes: newItemModels,
    }
  })

  const removeFromPageType = getPageTypeFromQueryKey(queryKeyToRemoveFrom)
  const addToPageType =
    'overItemId' in reorderItemData
      ? getPageTypeFromQueryKey(queryKeyToAddTo)
      : {groupId: reorderItemData.overGroupId, secondaryGroupId: reorderItemData.overSecondaryGroupId}

  if (isPageTypeForGroupedItems(removeFromPageType) && isPageTypeForGroupedItems(addToPageType)) {
    const newTotalCounts: Omit<MemexItemsTotalCountsQueryData, 'totalCount'> = {
      groups: {},
    }

    if (removeFromPageType.groupId !== addToPageType.groupId) {
      const removeFromGroupId = removeFromPageType.groupId
      const addToGroupId = addToPageType.groupId
      newTotalCounts.groups[removeFromGroupId] = incrementMemexItemsTotalCountForGroup(
        queryClient,
        variables,
        removeFromGroupId,
        -1,
      )
      newTotalCounts.groups[addToGroupId] = incrementMemexItemsTotalCountForGroup(
        queryClient,
        variables,
        addToGroupId,
        1,
      )
    }

    if (
      removeFromPageType.secondaryGroupId !== addToPageType.secondaryGroupId &&
      removeFromPageType.secondaryGroupId != null &&
      addToPageType.secondaryGroupId != null
    ) {
      const removeFromGroupId = removeFromPageType.secondaryGroupId
      const addToGroupId = addToPageType.secondaryGroupId
      newTotalCounts.groups[removeFromGroupId] = incrementMemexItemsTotalCountForGroup(
        queryClient,
        variables,
        removeFromGroupId,
        -1,
      )
      newTotalCounts.groups[addToGroupId] = incrementMemexItemsTotalCountForGroup(
        queryClient,
        variables,
        addToGroupId,
        1,
      )
    }

    mergeQueryDataForMemexItemsTotalCounts(queryClient, variables, newTotalCounts)
  }

  if ('overItemId' in reorderItemData) {
    return {previousItemId, rollbackData}
  } else {
    // We don't want to return anything  for the previousItemId if we're adding to an empty group
    // as it should not represent a change in priority, just a change in the group value
    return {previousItemId: undefined, rollbackData}
  }
}

/**
 * Optimistically repositions an item in the list based on a new index. Also returns some information that
 * will be needed in the request to the server to reposition the item.
 * @param queryClient
 * @param id Id of item to move
 * @param index New index of item
 * @returns {previousItemId, previousMovingItemIndex}: The id of the item that the moving item should be placed after
 * (or "" if it is the first item), and the old index of the item that we're moving. If the item cannot be found, returns
 * {previousItemId: -1}
 */
export function updateMemexItemWitNewRowPositionInQueryClient(queryClient: QueryClient, id: number, index: number) {
  if (shouldUseSinglePageQuery()) {
    const itemIndex = findMemexItemGlobalIndexByIdInQueryClient(queryClient, id)

    const queryData = queryClient.getQueryData<UseMemexItemsQueryData>(getKey(queryClient))
    const oldItemModels = getItemsFromQueryData(queryData) || []

    const item = oldItemModels[itemIndex]

    if (!item) {
      return {previousItemId: -1}
    }

    // Server API expects empty string if repositioning to the first spot
    let previousItemId: number | '' = ''
    if (index > 0) {
      // If we are moving an item down (itemIndex < index), then we want to use the item at the index
      // passed to this function, because that item will be shifted up.
      // If we are moving an item up (itemIndex > index), then we want to use the item one before the index
      // passed to this function, because that item will not be moving at all
      const previousItem = itemIndex < index ? oldItemModels[index] : oldItemModels[index - 1]
      if (previousItem) previousItemId = previousItem.id
    }

    const newItemModels = [...oldItemModels]
    // Remove the item from its current position
    newItemModels.splice(itemIndex, 1)
    // Re-add the item in its new position
    newItemModels.splice(index, 0, item)

    queryClient.setQueryData<UseMemexItemsQueryData>(getKey(queryClient), createQueryDataFromItems(newItemModels))

    return {previousItemId, previousMovingItemIndex: itemIndex}
  } else {
    // Technically we could do these two things in one loop, but we're starting here with this simple approach first
    const initialIndexOfTheItemWeWantToMove = findMemexItemGlobalIndexByIdInQueryClient(queryClient, id)
    const item = findMemexItemByIdInQueryClient(queryClient, id)
    if (!item) return {previousItemId: -1}

    // The API expects empty string if repositioning to the first spot
    let previousItemId: number | '' = ''

    let currentGlobalIndex = 0
    queryClient.setQueriesData<MemexPageQueryData>(activeMemexItemsQueryFilter, queryData => {
      if (!isQueryPageOfItems(queryData)) {
        return queryData
      }

      const globalIndexBeforeThisPage = currentGlobalIndex
      currentGlobalIndex = currentGlobalIndex + queryData.nodes.length

      const oldItemNeedsToBeRemovedOnThisPage =
        initialIndexOfTheItemWeWantToMove >= globalIndexBeforeThisPage &&
        initialIndexOfTheItemWeWantToMove < currentGlobalIndex
      const newItemNeedsToBeAddedOnThisPage = index >= globalIndexBeforeThisPage && index < currentGlobalIndex

      // no work to be done on this page
      if (!oldItemNeedsToBeRemovedOnThisPage && !newItemNeedsToBeAddedOnThisPage) return queryData

      // if index is 0 we should leave previousItemId as '' to indicate it's the first position
      if (newItemNeedsToBeAddedOnThisPage && index > 0) {
        // If we are moving an item down (itemIndex < index), then we want to find the item at the same index that
        // was passed to this function because that item will be shifted up.
        //
        // If we are moving an item up (itemIndex > index), then we want to find the item one before the index
        // passed to this function because that item will not be moving at all.
        const indexToFindPreviousItem =
          initialIndexOfTheItemWeWantToMove < index
            ? index - globalIndexBeforeThisPage
            : index - globalIndexBeforeThisPage - 1

        const previousItem = queryData.nodes[indexToFindPreviousItem]
        if (previousItem) previousItemId = previousItem.id
      }

      const newPageNodes = [...queryData.nodes]

      // First remove the item from its current position
      // if it is in the page we are currently looking at

      if (oldItemNeedsToBeRemovedOnThisPage) {
        newPageNodes.splice(newPageNodes.indexOf(item), 1)
      }

      // Next, add the item at its new position
      // if it is in the page we are currently looking at
      if (newItemNeedsToBeAddedOnThisPage) {
        // If we already removed the item from this page,
        // we need to adjust the index to account for that
        const indexToAddItemAt =
          initialIndexOfTheItemWeWantToMove < index
            ? index - globalIndexBeforeThisPage - (oldItemNeedsToBeRemovedOnThisPage ? 0 : 1)
            : index - globalIndexBeforeThisPage
        newPageNodes.splice(indexToAddItemAt, 0, item)
      }

      return {...queryData, nodes: newPageNodes}
    })

    return {previousItemId, previousMovingItemIndex: initialIndexOfTheItemWeWantToMove}
  }
}

/**
 * Updates the local state of a MemexItemModel with new values from the server. If the item cannot be found, nothing happens;
 * otherwise, a new MemexItemModel is created to replace the existing item in our client-side state and a new array identity
 * is created, so that a re-render is triggered.
 * @param queryClient
 * @param newMemexItem New data that we're looking to merge values into an existingMemexItemModel in our client state
 */
export function updateMemexItemInQueryClient(
  queryClient: QueryClient,
  newMemexItem: MemexItem | UpdateMemexItemResponseData,
  skipSidePanel: boolean = false,
) {
  if (!skipSidePanel) {
    updateSidePanelItemInQueryClient(queryClient, newMemexItem)
  }
  if (shouldUseSinglePageQuery()) {
    const foundIndex = findMemexItemGlobalIndexByIdInQueryClient(queryClient, newMemexItem.id)

    if (foundIndex === -1) {
      return
    }

    queryClient.setQueryData<UseMemexItemsQueryData>(getKey(queryClient), queryData => {
      const oldMemexItemModels = getItemsFromQueryData(queryData)
      const newMemexItemModels = [...(oldMemexItemModels || [])]
      const oldItemModel = newMemexItemModels[foundIndex]
      if (oldItemModel) {
        const mergedItem = mergeItemData(oldItemModel, newMemexItem)
        if (mergedItem) {
          const newItemModel = createMemexItemModel(mergedItem)
          newMemexItemModels[foundIndex] = newItemModel
          return createQueryDataFromItems(newMemexItemModels)
        }
      }
      return queryData
    })
  } else {
    // The general algorithm here is as follows:
    // Find the query key of the query that contains the item we're looking to update.
    // Then call `setQueryData` with that query key, and find the index of the item in the page/query.
    // Next, we merge the item data, and update the item in the page/query, and return the new array of nodes.
    const queryKeyForQueryContainingItem = getQueryKeyForItem(queryClient, newMemexItem.id)
    if (!queryKeyForQueryContainingItem) {
      // Return early if the item is not in the main query cache
      return
    }
    queryClient.setQueryData<MemexItemsPageQueryData>(queryKeyForQueryContainingItem, queryData => {
      if (!queryData) {
        return createPageQueryDataFromItems([])
      }
      const newPageNodes = [...queryData.nodes]
      const indexOnPage = newPageNodes.findIndex(item => item.id === newMemexItem.id)
      const itemModel = newPageNodes[indexOnPage]
      if (itemModel) {
        const mergedItem = mergeItemData(itemModel, newMemexItem)
        if (mergedItem) {
          const newItemModel = createMemexItemModel(mergedItem)
          newPageNodes[indexOnPage] = newItemModel
        }
      }
      return {...queryData, nodes: newPageNodes}
    })
  }
}

/**
 * Checks if there are title column changes on live updates, specifically issue state and title
 * @param currentItemModel Current memex item before merge
 * @param newMemexItem New data that we're looking to merge values into
 */
function hasTileColumnChange(currentItemModel: MemexItemModel, newMemexItem: MemexItem) {
  // Exit if items aren't both issues
  if (currentItemModel.contentType !== ItemType.Issue || newMemexItem.contentType !== ItemType.Issue) {
    return false
  }

  // we don't need to check for stateReason because a not-planned issue needs to be open
  if (currentItemModel.state !== newMemexItem.state) {
    return true
  }

  const currentItemTitle = currentItemModel.getRawTitle()
  const newMemexItemTitle = createMemexItemModel(newMemexItem).getRawTitle()

  if (currentItemTitle !== newMemexItemTitle) {
    return true
  }

  return false
}

/**
 * Performs a bulk update/merge of memex item client state with a new list of items from the server.
 * Will create new MemexItemModels and merge data unless the model is marked with `skippingLiveUpdates` or
 * the item's id matches the sidePanelStateItemId parameter.
 * @param queryClient
 * @param newMemexItems full list of new memex items to merge state with existing items
 * @param sidePanelStateItemId optional parameter indicating that an item is open in the side panel
 * and we should therefore skip merging in any data to its client state
 */
export function updateMemexItemsInQueryClient(
  queryClient: QueryClient,
  newMemexItems: Array<MemexItem>,
  sidePanelStateItemId: number | undefined,
) {
  if (shouldUseSinglePageQuery()) {
    queryClient.setQueryData<UseMemexItemsQueryData>(getKey(queryClient), queryData => {
      const oldMemexItemModels = getItemsFromQueryData(queryData)
      const newMemexItemModels: Array<MemexItemModel> = []

      // Build a look-up map of MemexItemModels by id, to avoid the O(n) look-up for each item in newMemexItemModels
      // that would occur as part of findMemexItemByIdInQueryClient
      const oldMemexItemModelsMap = (oldMemexItemModels || []).reduce(
        (prev, curr) => {
          prev[curr.id] = curr
          return prev
        },
        {} as {[id: number]: MemexItemModel},
      )

      for (const item of newMemexItems) {
        let currentItemModel = oldMemexItemModelsMap[item.id]
        // This check covers three cases:
        // 1. Creating a new model for the first time
        // 2. Updating an existing model when the item exists and not skipping live updates
        // 3. Updating an existing model when the item exists and is open in the side panel unless there's an issue
        //    state changes, eg: closed => open

        if (!currentItemModel) {
          currentItemModel = createMemexItemModel(item)
        } else if (
          !currentItemModel.skippingLiveUpdates &&
          (currentItemModel.id !== sidePanelStateItemId || hasTileColumnChange(currentItemModel, item))
        ) {
          const nextItemState = mergeItemData(currentItemModel, item)

          currentItemModel = nextItemState ? createMemexItemModel(nextItemState) : currentItemModel
        }
        newMemexItemModels.push(currentItemModel)
      }

      return createQueryDataFromItems(newMemexItemModels)
    })
  } else {
    // The general algorithm here is as follows:
    // Build up a map of new items by id, so that we can easily look up items by id
    // Call `setQueriesData` to iterate over each active query/page in the query client,
    // and then iterate over each item in that page. Update the item if appropriate, and
    // remove it from our map of items. After iterating over all items in the page, return
    // the new list of items as the query data for that query.
    const newMemexItemsById = (newMemexItems || []).reduce(
      (accumulator, memexItem) => {
        accumulator[memexItem.id] = memexItem
        return accumulator
      },
      {} as {[id: number]: MemexItem},
    )

    const setQueriesDataResult = queryClient.setQueriesData<MemexPageQueryData>(
      activeMemexItemsQueryFilter,
      queryData => {
        if (!isQueryPageOfItems(queryData)) {
          return queryData
        }

        const newPageNodes = [...queryData.nodes]

        for (const [indexOnPage, existingItemModel] of queryData.nodes.entries()) {
          const itemToUpdate = newMemexItemsById[existingItemModel.id]
          // if this item is skipping live updates or is open in the side panel, then we should skip updating it in
          // the cache
          if (existingItemModel.skippingLiveUpdates || existingItemModel.id === sidePanelStateItemId) {
            delete newMemexItemsById[existingItemModel.id]
          } else if (itemToUpdate) {
            const nextItemState = mergeItemData(existingItemModel, itemToUpdate)
            if (nextItemState) {
              newPageNodes.splice(indexOnPage, 1, createMemexItemModel(nextItemState))
              delete newMemexItemsById[itemToUpdate.id]
            }
          }
        }
        return {...queryData, nodes: newPageNodes}
      },
    )

    // Once we have iterated over all of the items in all of the queries, we may have some
    // items still in newMemexItemsById if they didn't previously exist. We want to add these
    // items to the last query in the list, so that they are added to the end of the list.
    // Our initial setQueriesData call returns an array of arrays, where the first element is the query key.
    // We use this to get the last query key in the list, so that we can simply call `setQueryData` with
    // an exact query key, instead of having to iterate over all of the queries again with `seQueriesData`.

    const lastQueryKey = setQueriesDataResult[setQueriesDataResult.length - 1]?.[0]

    if (lastQueryKey && Object.keys(newMemexItemsById).length > 0) {
      queryClient.setQueryData<MemexItemsPageQueryData>(lastQueryKey, queryData => {
        if (!queryData) {
          return createPageQueryDataFromItems([])
        }
        const newPageNodes = [...queryData.nodes]
        // add items that do not exist yet
        if (Object.keys(newMemexItemsById).length > 0) {
          for (const newItem of Object.values(newMemexItemsById)) {
            newPageNodes.push(createMemexItemModel(newItem))
          }
        }
        return {...queryData, nodes: newPageNodes}
      })
    }
  }
}

/**
 * Updates the column data values for a given column for all items.
 * Sets an item's column value to 'null' if no column data is provided
 * for that item.
 * @param queryClient
 * @param columnWithItems The column and new item values to update to
 */
export function updateMemexItemsForColumnInQueryClient(queryClient: QueryClient, columnWithItems: IColumnWithItems) {
  if (shouldUseSinglePageQuery()) {
    // Build up a map for our new column values to avoid O(n^2) look-up in the
    // second for loop
    const newColumnValuesByItemId: {[itemId: number]: MemexColumnData} = {}
    if (columnWithItems.memexProjectColumnValues) {
      for (const columnData of columnWithItems.memexProjectColumnValues) {
        newColumnValuesByItemId[columnData.memexProjectItemId] = {
          memexProjectColumnId: columnWithItems.id,
          value: columnData.value,
        } as MemexColumnData
      }
    }
    queryClient.setQueryData<UseMemexItemsQueryData>(getKey(queryClient), queryData => {
      const oldMemexItemModels = getItemsFromQueryData(queryData)
      const newMemexItemModels = [...(oldMemexItemModels || [])]
      for (const itemModel of newMemexItemModels) {
        let newValue: MemexColumnData | undefined = newColumnValuesByItemId[itemModel.id]
        // If we don't have a value, we need to create one with a value of null
        if (!newValue?.value) {
          newValue = {memexProjectColumnId: columnWithItems.id, value: null} as MemexColumnData
        }
        // When we've received a column values for a single column across multiple items, `setColumnValueForItemColumnType`
        // will only update the `columnData` property, not the underlying `memexProjectColumnValues`
        // array. Normally, this isn't an issue, because we only interact directly the the column data -
        // except in the case of merging an item model, like when opening the side panel.
        // By calling `addNewColumnValue`, here, we ensure the `memexProjectColumnValues` are properly updated
        // and that we don't lose certain column data - which could lead to a bug like
        // https://github.com/github/projects-platform/issues/2615
        itemModel.addNewColumnValue(newValue)
      }
      return createQueryDataFromItems(newMemexItemModels)
    })
  } else {
    // Build up a map for our new column values to avoid O(n^2) look-up in the
    // second for loop
    const newColumnValuesByItemId: {[itemId: number]: MemexColumnData} = {}
    if (columnWithItems.memexProjectColumnValues) {
      for (const columnData of columnWithItems.memexProjectColumnValues) {
        newColumnValuesByItemId[columnData.memexProjectItemId] = {
          memexProjectColumnId: columnWithItems.id,
          value: columnData.value,
        } as MemexColumnData
      }
    }
    queryClient.setQueriesData<MemexPageQueryData>(activeMemexItemsQueryFilter, queryData => {
      if (!isQueryPageOfItems(queryData)) {
        return queryData
      }

      const newPageNodes = [...queryData.nodes]
      for (const itemModel of newPageNodes) {
        let newValue: MemexColumnData | undefined = newColumnValuesByItemId[itemModel.id]
        // If we don't have a value, we need to create one with a value of null
        if (!newValue?.value) {
          newValue = {memexProjectColumnId: columnWithItems.id, value: null} as MemexColumnData
        }
        itemModel.setColumnValueForItemColumnType(newValue)
      }
      return {...queryData, nodes: newPageNodes}
    })
  }
}

/**
 * Finds data for a given side panel itemId in the query cache
 * Returns undefined if no data is found
 */
export function getQueryDataForSidePanelItemFromQueryClient(queryClient: QueryClient, itemId: string | null) {
  if (!itemId || !parseInt(itemId)) return undefined
  return queryClient.getQueryData<MemexItemModel | undefined>(useSidePanelItemQuery.getKey({itemId}))
}

/**
 * Finds initial data for a given side panel itemId in the query cache
 * - First checks the side panel query cache
 * - Then checks the main items query cache
 * Returns undefined if no data is found
 */
export function getInitialDataForSidePanelItem(queryClient: QueryClient, itemId: string | number | null) {
  if (!itemId) return undefined
  const parsedItemId = Number(itemId)
  const existingData = queryClient.getQueryData<MemexItemModel | undefined>(
    useSidePanelItemQuery.getKey({itemId: parsedItemId.toString()}),
  )
  if (existingData) return existingData
  return findMemexItemByIdInQueryClient(queryClient, parsedItemId)
}

/**
 * A wrapper around setQueryData for setting query data for a single memex item model
 * that we want to show in the side panel.
 * If the item model is already in the main client-side state, updates that
 * copy of the item too.
 */
export function setQueryDataForSidePanelItemInQueryClient(queryClient: QueryClient, queryData: MemexItemModel) {
  const itemInMainCache = findMemexItemByIdInQueryClient(queryClient, queryData.id)
  const sidePanelQueryKey = useSidePanelItemQuery.getKey({itemId: queryData.id.toString()})
  if (itemInMainCache) {
    // If the item exists in the main query cache, update it
    updateMemexItemInQueryClient(queryClient, queryData, true)
  }
  // Always set item in the side panel cache.
  queryClient.setQueryData<MemexItemModel>(sidePanelQueryKey, queryData)
}

export function getItemsFromQueryData(queryData?: UseMemexItemsQueryData): Array<MemexItemModel> | undefined {
  return queryData?.pages[0]?.nodes
}

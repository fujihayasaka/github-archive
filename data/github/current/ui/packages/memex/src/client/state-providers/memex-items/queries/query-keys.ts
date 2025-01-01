import type {Query} from '@tanstack/react-query'

import type {MemexItem} from '../../../api/memex-items/contracts'
import type {GroupedMemexItems} from '../../../api/memex-items/paginated-views'
import {
  type FieldMetricsQueryVariables,
  type GroupedItemBatchPageParam,
  type PageParam,
  pageParamForInitialPage,
  type PaginatedMemexItemsQueryVariables,
  type SliceByQueryVariables,
  type TotalCountsQueryVariables,
} from './types'

export const paginatedMemexItemsQueryKey = 'paginatedMemexItems'
export const pageParamsQueryKey = 'pageParamsData'
export const sliceByDataQueryKey = 'sliceByData'
export const totalCountsQueryKey = 'paginatedTotalCounts'
export const fieldMetricsQueryKey = 'fieldMetrics'
export const sidePanelItemNotOnClientQueryKey = 'side-panel-item-not-on-client'
export const sidePanelItemQueryKey = 'sidePanelItem'

export const pageTypeForUngroupedItems = 'ungrouped'
export const pageTypeForGroups = 'groups'
export const pageTypeForSecondaryGroups = 'secondaryGroups'
export const pageTypeForGroupedItemBatches = 'groupedItemBatches'
export type PageTypeForUngroupedItems = typeof pageTypeForUngroupedItems
export type PageTypeForGroups = typeof pageTypeForGroups
export type PageTypeForSecondaryGroups = typeof pageTypeForSecondaryGroups
export type PageTypeForGroupedItemBatches = typeof pageTypeForGroupedItemBatches
export type GroupId = string
export type PageTypeForGroupedItems = {groupId: GroupId; secondaryGroupId?: GroupId}

// We explicitly do not include the PageTypeForGroupedItemBatches here, as there are only
// a few places where we want to consider that page type, so we instead prefer to explicitly
// use PageType | PageTypeForGroupedItemBatches in those scenarios.
export type PageType =
  | PageTypeForGroupedItems
  | PageTypeForUngroupedItems
  | PageTypeForGroups
  | PageTypeForSecondaryGroups

// This needs to be a value that cannot exist in the server-generated group ids
const groupedItemsIdSeparator = ':'

export type MemexGroupedItemsQueryKey = [
  'memex',
  typeof paginatedMemexItemsQueryKey,
  PaginatedMemexItemsQueryVariables,
  PageTypeForGroupedItems,
  PageParam,
]

export type MemexUngroupedItemsQueryKey = [
  'memex',
  typeof paginatedMemexItemsQueryKey,
  PaginatedMemexItemsQueryVariables,
  PageTypeForUngroupedItems,
  PageParam,
]

export type MemexGroupsQueryKey = [
  'memex',
  typeof paginatedMemexItemsQueryKey,
  PaginatedMemexItemsQueryVariables,
  PageTypeForGroups,
  PageParam,
]

export type MemexSecondaryGroupsQueryKey = [
  'memex',
  typeof paginatedMemexItemsQueryKey,
  PaginatedMemexItemsQueryVariables,
  PageTypeForSecondaryGroups,
  PageParam,
]

export type GroupedItemBatchQueryKey = [
  'memex',
  typeof paginatedMemexItemsQueryKey,
  PaginatedMemexItemsQueryVariables,
  PageTypeForGroupedItemBatches,
  GroupedItemBatchPageParam,
]

export type PaginatedMemexItemsQueryKey =
  | MemexGroupedItemsQueryKey
  | MemexUngroupedItemsQueryKey
  | MemexGroupsQueryKey
  | MemexSecondaryGroupsQueryKey

export const buildMemexItemsOrGroupsQueryKey = (
  variables: PaginatedMemexItemsQueryVariables,
  pageType: PageType,
  pageParam: PageParam,
): PaginatedMemexItemsQueryKey => {
  return ['memex', paginatedMemexItemsQueryKey, variables, pageType, pageParam]
}

export function buildMemexUngroupedItemsQueryKey(
  variables: PaginatedMemexItemsQueryVariables,
  pageParam: PageParam,
): MemexUngroupedItemsQueryKey {
  return ['memex', paginatedMemexItemsQueryKey, variables, pageTypeForUngroupedItems, pageParam]
}

export function buildMemexGroupsQueryKey(
  variables: PaginatedMemexItemsQueryVariables,
  pageParam: PageParam,
): MemexGroupsQueryKey {
  return ['memex', paginatedMemexItemsQueryKey, variables, pageTypeForGroups, pageParam]
}

export function buildMemexSecondaryGroupsQueryKey(
  variables: PaginatedMemexItemsQueryVariables,
  pageParam: PageParam,
): MemexSecondaryGroupsQueryKey {
  return ['memex', paginatedMemexItemsQueryKey, variables, pageTypeForSecondaryGroups, pageParam]
}

export function buildMemexGroupedItemsQueryKey(
  variables: PaginatedMemexItemsQueryVariables,
  pageType: PageTypeForGroupedItems,
  pageParam: PageParam,
): MemexGroupedItemsQueryKey {
  return ['memex', paginatedMemexItemsQueryKey, variables, pageType, pageParam]
}

export function buildGroupedItemBatchQueryKey(
  variables: PaginatedMemexItemsQueryVariables,
  pageParam: GroupedItemBatchPageParam,
): GroupedItemBatchQueryKey {
  return ['memex', paginatedMemexItemsQueryKey, variables, pageTypeForGroupedItemBatches, pageParam]
}

export type PageParamsQueryKey = [
  'memex',
  typeof paginatedMemexItemsQueryKey,
  PaginatedMemexItemsQueryVariables,
  typeof pageParamsQueryKey,
]

export type SliceByDataQueryKey = [
  'memex',
  typeof paginatedMemexItemsQueryKey,
  PaginatedMemexItemsQueryVariables,
  typeof sliceByDataQueryKey,
]

export type TotalCountsDataQueryKey = [
  'memex',
  typeof paginatedMemexItemsQueryKey,
  PaginatedMemexItemsQueryVariables,
  typeof totalCountsQueryKey,
]

export type FieldMetricsQueryKey = [
  'memex',
  typeof paginatedMemexItemsQueryKey,
  PaginatedMemexItemsQueryVariables,
  typeof fieldMetricsQueryKey,
]

export const buildPageParamsQueryKey = (variables: PaginatedMemexItemsQueryVariables): PageParamsQueryKey => {
  return ['memex', paginatedMemexItemsQueryKey, variables, pageParamsQueryKey]
}

export const buildSliceDataQueryKey = (variables: PaginatedMemexItemsQueryVariables): SliceByDataQueryKey => {
  const sliceByVariables: SliceByQueryVariables = {...variables, sliceByValue: undefined, fieldIds: undefined}
  return ['memex', paginatedMemexItemsQueryKey, sliceByVariables, sliceByDataQueryKey]
}

export const buildPaginatedTotalCountsQueryKey = (
  variables: PaginatedMemexItemsQueryVariables,
): TotalCountsDataQueryKey => {
  const totalCountsVariables: TotalCountsQueryVariables = {...variables, fieldIds: undefined}
  return ['memex', paginatedMemexItemsQueryKey, totalCountsVariables, totalCountsQueryKey]
}

export const buildFieldMetricsQueryKey = (variables: PaginatedMemexItemsQueryVariables): FieldMetricsQueryKey => {
  const totalCountsVariables: FieldMetricsQueryVariables = {...variables, fieldIds: undefined}
  return ['memex', paginatedMemexItemsQueryKey, totalCountsVariables, fieldMetricsQueryKey]
}

/**
 * A utility method for looking up the pageType from a `react-query` `QueryKey`. The `QueryKey`
 * is implemented as an Array under the hood.
 * @param queryKey A query key for paginated memex items data.
 * @returns The pageType from the query key.
 */
export const getPageTypeFromQueryKey = (queryKey: PaginatedMemexItemsQueryKey): PageType => {
  return queryKey[3]
}

export const isQueryKeyForGroups = (queryKey: PaginatedMemexItemsQueryKey): queryKey is MemexGroupsQueryKey => {
  // A query key that looks like:
  // ['paginatedMemexItems', {q: '', sortedBy: [], horizontalGroupedByColumnId: 'Status'}, "groups", undefined]
  // Represents a page of groups
  return queryKey[3] === pageTypeForGroups
}

export const isQueryKeyForSecondaryGroups = (
  queryKey: PaginatedMemexItemsQueryKey,
): queryKey is MemexSecondaryGroupsQueryKey => {
  // A query key that looks like:
  // ['paginatedMemexItems', {q: '', sortedBy: [], horizontalGroupedByColumnId: 'Status', verticalGroupedByColumnId: 'Assignees'}, "secondaryGroups", undefined]
  // Represents a page of secondary groups
  return queryKey[3] === pageTypeForSecondaryGroups
}

export const isQueryKeyForGroupedItems = (
  queryKey: PaginatedMemexItemsQueryKey,
): queryKey is MemexGroupedItemsQueryKey => {
  // A query key that looks like:
  // ['paginatedMemexItems', {q: '', sortedBy: [], horizontalGroupedByColumnId: 'Status'}, {groupId: 'groupId1'}, undefined]
  // Represents a page of grouped items (i.e. the intersection of a primary and secondary group)
  return isPageTypeForGroupedItems(queryKey[3])
}

/**
 * A utility method determining whether a given `queryKey` represents the query which
 * initially populates the view.
 * When a view is ungrouped, this means the initial page of items.
 * When a view is grouped, this means the initial page of groups, which seeds the initial
 * pages of groupedItems and (potentially) an initial secondary groups.
 */
export const isInitialQueryKeyForView = (queryKey: PaginatedMemexItemsQueryKey): boolean => {
  const isPageTypeForGroupsOrUngroupedItems =
    queryKey[3] === pageTypeForGroups || queryKey[3] === pageTypeForUngroupedItems
  return queryKey[4] === pageParamForInitialPage && isPageTypeForGroupsOrUngroupedItems
}

/**
 * A utility method determining whether a given `PageType` represents a page of grouped items.
 */
export const isPageTypeForGroupedItems = (pageType: NonNullable<unknown>): pageType is PageTypeForGroupedItems => {
  return typeof pageType === 'object' && 'groupId' in pageType
}

/**
 * A utility method determining whether a given `PageType` represents a page of items.
 * The page of items may be grouped or ungrouped.
 */
export const isPageOfItems = (pageType: PageType): pageType is PageTypeForGroupedItems | PageTypeForUngroupedItems => {
  return isPageTypeForGroupedItems(pageType) || pageType === pageTypeForUngroupedItems
}

export const createGroupedItemsPageType = (group: GroupedMemexItems<MemexItem>): PageTypeForGroupedItems => {
  return {groupId: group.groupId, secondaryGroupId: group.secondaryGroupId}
}

export const createGroupedItemsPageTypeFromGroupedItemsId = (groupedItemsId: string): PageTypeForGroupedItems => {
  const indexOfSeparator = groupedItemsId.indexOf(groupedItemsIdSeparator)
  if (indexOfSeparator !== -1) {
    return {
      groupId: groupedItemsId.substring(0, indexOfSeparator),
      secondaryGroupId: groupedItemsId.substring(indexOfSeparator + groupedItemsIdSeparator.length),
    }
  } else {
    return {groupId: groupedItemsId}
  }
}

export const createGroupedItemsId = (pageType: PageTypeForGroupedItems) => {
  if (pageType.secondaryGroupId) {
    // Build a string that looks like `groupId1:secondaryGroupId1`
    return `${pageType.groupId}${groupedItemsIdSeparator}${pageType.secondaryGroupId}`
  } else {
    return pageType.groupId
  }
}

/**
 * Given a single query, checks to see whether or not the query represents data
 * indirectly related to memex items or groups, e.g. Page Params, Total Counts, Slice By Data, etc.
 *
 * This helper is used as the `predicate` when filtering queries with `get`/`setQueriesData`.
 *
 * All queries in the query cache related to memex items and groups live under a top-level
 * 'paginatedMemexItems` query key, so we use that top-level query key when we want to inspect or
 * modify all of these queries broadly, like during cache invalidation.
 *
 * However, we often _do not_ want to consider the sort of ancillary data referenced in this function,
 * so by using this function as a predicate, we can filter these queries out early by inspecting
 * the last part of the query key.
 */
export const isQueryForItemsMetadata = (query: Query<unknown, Error, unknown>) => {
  const queryKey = query.queryKey
  const lastPartOfQueryKey = queryKey[queryKey.length - 1]
  return (
    lastPartOfQueryKey === pageParamsQueryKey ||
    lastPartOfQueryKey === totalCountsQueryKey ||
    lastPartOfQueryKey === sliceByDataQueryKey
  )
}

/**
 * Given a single query, checks to see whether or not the query relates to a page of memex items data.
 * This is determined by checking the page type of the query's query key.
 *
 * If it is for ungrouped items or grouped items, the query is for items data.
 */
export const isQueryForItems = (query: Query<unknown, Error, unknown>) => {
  const queryKey = query.queryKey
  const pageTypePart = queryKey[queryKey.length - 2]
  return pageTypePart != null && (pageTypePart === pageTypeForUngroupedItems || isPageTypeForGroupedItems(pageTypePart))
}

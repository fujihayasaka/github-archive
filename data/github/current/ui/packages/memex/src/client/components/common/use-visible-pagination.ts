import {useEffect, useMemo, useRef} from 'react'

import type {PageTypeForGroupedItems} from '../../state-providers/memex-items/queries/query-keys'
import {usePaginatedMemexItemsQuery} from '../../state-providers/memex-items/queries/use-paginated-memex-items-query'
import useIsVisible from '../board/hooks/use-is-visible'

export const useUngroupedVisiblePagination = () => {
  const ref = useRef<HTMLDivElement | null>(null)
  const {isVisible} = useIsVisible({ref})
  const prevIsVisible = useRef<boolean>(false)
  const {isFetchingNextPage, fetchNextPage, hasNextPage, hasInitialData} = usePaginatedMemexItemsQuery()

  useEffect(() => {
    // If visibility hasn't changed between renders
    // or the element is not visible, we can return early.
    //
    // This protects against triggering unnecessary requests
    // when a component is re-rendered for reasons other than visibility,
    // E.g., because a pageType object isn't referencially equal or the
    // top-level isFetchingNextPage changes, but the ref is for groupedItems.
    if (prevIsVisible.current === isVisible) return
    prevIsVisible.current = isVisible
    if (!isVisible) return

    if (hasNextPage && !isFetchingNextPage && hasInitialData) {
      fetchNextPage()
    }
  }, [fetchNextPage, hasInitialData, hasNextPage, isFetchingNextPage, isVisible])

  return useMemo(() => {
    return {
      ref,
      isVisible,
      hasNextPage,
    }
  }, [hasNextPage, isVisible])
}

export const useGroupsVisiblePagination = () => {
  const ref = useRef<HTMLDivElement | null>(null)
  const {isVisible} = useIsVisible({ref})
  const prevIsVisible = useRef<boolean>(false)
  const {isFetchingNextPage, fetchNextPage, hasNextPage, hasInitialData} = usePaginatedMemexItemsQuery()

  useEffect(() => {
    // If visibility hasn't changed between renders
    // or the element is not visible, we can return early.
    //
    // This protects against triggering unnecessary requests
    // when a component is re-rendered for reasons other than visibility,
    // E.g., because a pageType object isn't referencially equal or the
    // top-level isFetchingNextPage changes, but the ref is for groupedItems.
    if (prevIsVisible.current === isVisible) return
    prevIsVisible.current = isVisible
    if (!isVisible) return

    if (hasNextPage && !isFetchingNextPage && hasInitialData) {
      fetchNextPage()
    }
  }, [fetchNextPage, hasInitialData, hasNextPage, isFetchingNextPage, isVisible])

  return useMemo(() => {
    return {
      ref,
      isVisible,
      hasNextPage,
    }
  }, [hasNextPage, isVisible])
}

export const useSecondaryGroupsVisiblePagination = () => {
  const ref = useRef<HTMLDivElement | null>(null)
  const {isVisible} = useIsVisible({ref})
  const prevIsVisible = useRef<boolean>(false)
  const {
    isFetchingNextPageForSecondaryGroups,
    fetchNextPageForSecondaryGroups,
    hasNextPageForSecondaryGroups,
    hasInitialData,
  } = usePaginatedMemexItemsQuery()

  useEffect(() => {
    // If visibility hasn't changed between renders
    // or the element is not visible, we can return early.
    //
    // This protects against triggering unnecessary requests
    // when a component is re-rendered for reasons other than visibility,
    // E.g., because a pageType object isn't referencially equal or the
    // top-level isFetchingNextPage changes, but the ref is for groupedItems.
    if (prevIsVisible.current === isVisible) return
    prevIsVisible.current = isVisible
    if (!isVisible) return

    if (hasNextPageForSecondaryGroups && !isFetchingNextPageForSecondaryGroups && hasInitialData) {
      fetchNextPageForSecondaryGroups()
    }
  }, [
    fetchNextPageForSecondaryGroups,
    hasInitialData,
    hasNextPageForSecondaryGroups,
    isFetchingNextPageForSecondaryGroups,
    isVisible,
  ])

  return useMemo(() => {
    return {
      ref,
      isVisible,
      hasNextPage: hasNextPageForSecondaryGroups,
    }
  }, [hasNextPageForSecondaryGroups, isVisible])
}

export const useGroupedItemsVisiblePagination = (pageType: PageTypeForGroupedItems) => {
  const ref = useRef<HTMLDivElement | null>(null)
  const {isVisible} = useIsVisible({ref})
  const {isFetchingNextPageForGroupedItems, fetchNextPageForGroupedItems, hasNextPageForGroupedItems} =
    usePaginatedMemexItemsQuery()

  useEffect(() => {
    if (!isVisible) return

    // The `pageType` is an object which could have a different reference across
    // renders, which means that we don't want it to be a dependency of this `useEffect`,
    // because that would lead to extra calls to `fetchNextPageForGroupedItems`. So,
    // we use the `pageType.groupId` and `pageType.secondaryGroupId` values directly
    // as the dependencies of this `useEffect`, as those strings should be stable, then
    // reconstruct a `PageTypeForGroupedItems` within the `useEffect` here.
    const stablePageType: PageTypeForGroupedItems = {
      groupId: pageType.groupId,
      secondaryGroupId: pageType.secondaryGroupId,
    }

    // A secondaryGroupId indicates this is a groupedItem cell (i.e., swimlane cell)
    // which is only paginated on-click, not when it becomes visible.
    if (!stablePageType.secondaryGroupId) {
      if (hasNextPageForGroupedItems(stablePageType) && !isFetchingNextPageForGroupedItems(stablePageType)) {
        fetchNextPageForGroupedItems(stablePageType)
      }
    }
  }, [
    fetchNextPageForGroupedItems,
    hasNextPageForGroupedItems,
    isFetchingNextPageForGroupedItems,
    isVisible,
    pageType.groupId,
    pageType.secondaryGroupId,
  ])

  return useMemo(() => {
    return {
      ref,
      isVisible,
      hasNextPage: hasNextPageForGroupedItems(pageType),
    }
  }, [hasNextPageForGroupedItems, isVisible, pageType])
}

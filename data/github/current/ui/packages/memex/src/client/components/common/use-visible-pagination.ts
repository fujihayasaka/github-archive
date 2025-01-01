import {useEffect, useMemo, useRef} from 'react'

import type {GroupId} from '../../state-providers/memex-items/queries/query-keys'
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
      hasNextPage,
    }
  }, [hasNextPage])
}

export const useGroupsVisiblePagination = (skipFetch = false) => {
  const ref = useRef<HTMLDivElement | null>(null)
  const {isVisible} = useIsVisible({ref})
  const prevIsVisible = useRef<boolean>(false)
  const {isFetchingNextPage, fetchNextPage, hasNextPage, hasInitialData} = usePaginatedMemexItemsQuery()

  useEffect(() => {
    // If visibility hasn't changed between renders
    // or the element is not visible, we can return early.
    //
    // This protects against triggering unnecessary requests
    // when a component is re-rendered for reasons other than visibility.
    if (prevIsVisible.current === isVisible) return
    prevIsVisible.current = isVisible
    if (!isVisible) return
    if (skipFetch) return

    if (hasNextPage && !isFetchingNextPage && hasInitialData) {
      fetchNextPage()
    }
  }, [fetchNextPage, hasInitialData, hasNextPage, isFetchingNextPage, isVisible, skipFetch])

  return useMemo(() => {
    return {
      ref,
      hasNextPage,
    }
  }, [hasNextPage])
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
      hasNextPage: hasNextPageForSecondaryGroups,
    }
  }, [hasNextPageForSecondaryGroups])
}

export const useSinglyGroupedItemsVisiblePagination = (groupId: GroupId) => {
  const ref = useRef<HTMLDivElement | null>(null)
  const {isVisible} = useIsVisible({ref})
  const {isFetchingNextPageForGroupedItems, fetchNextPageForGroupedItems, hasNextPageForGroupedItems} =
    usePaginatedMemexItemsQuery()

  useEffect(() => {
    if (!isVisible) return
    if (hasNextPageForGroupedItems({groupId}) && !isFetchingNextPageForGroupedItems({groupId})) {
      fetchNextPageForGroupedItems({groupId})
    }
  }, [fetchNextPageForGroupedItems, groupId, hasNextPageForGroupedItems, isFetchingNextPageForGroupedItems, isVisible])

  return useMemo(() => {
    return {
      ref,
      hasNextPage: hasNextPageForGroupedItems({groupId}),
    }
  }, [hasNextPageForGroupedItems, groupId])
}

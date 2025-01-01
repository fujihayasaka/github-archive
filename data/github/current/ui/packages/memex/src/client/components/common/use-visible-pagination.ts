import {useEffect, useMemo, useRef} from 'react'

import type {GroupId} from '../../state-providers/memex-items/queries/query-keys'
import {usePaginatedMemexItemsQuery} from '../../state-providers/memex-items/queries/use-paginated-memex-items-query'
import useIsVisible from '../board/hooks/use-is-visible'

export const useUngroupedVisiblePagination = () => {
  const ref = useRef<HTMLDivElement | null>(null)
  const {isVisible, isCurrentlyVisible} = useIsVisible({ref})
  const prevIsVisible = useRef<boolean>(false)
  const {isFetchingNextPage, fetchNextPage, hasNextPage, hasInitialData} = usePaginatedMemexItemsQuery()

  useEffect(() => {
    const readyForNextPage = shouldFetchNextPage({
      isVisible,
      hasInitialData,
      hasNextPage,
      isFetchingNextPage,
      skipFetch: false,
      isCurrentlyVisible,
      prevIsVisible,
    })
    if (readyForNextPage) {
      fetchNextPage()
    }
  }, [fetchNextPage, hasInitialData, hasNextPage, isFetchingNextPage, isVisible, isCurrentlyVisible])

  return useMemo(() => {
    return {
      ref,
      hasNextPage,
    }
  }, [hasNextPage])
}

export const useGroupsVisiblePagination = (skipFetch = false) => {
  const ref = useRef<HTMLDivElement | null>(null)
  const {isVisible, isCurrentlyVisible} = useIsVisible({ref})
  const prevIsVisible = useRef<boolean>(false)
  const {isFetchingNextPage, fetchNextPage, hasNextPage, hasInitialData} = usePaginatedMemexItemsQuery()

  useEffect(() => {
    const readyForNextPage = shouldFetchNextPage({
      isVisible,
      hasInitialData,
      hasNextPage,
      isFetchingNextPage,
      skipFetch,
      isCurrentlyVisible,
      prevIsVisible,
    })
    if (readyForNextPage) {
      fetchNextPage()
    }
  }, [fetchNextPage, hasInitialData, hasNextPage, isFetchingNextPage, isVisible, isCurrentlyVisible, skipFetch])

  return useMemo(() => {
    return {
      ref,
      hasNextPage,
    }
  }, [hasNextPage])
}

export const useSecondaryGroupsVisiblePagination = () => {
  const ref = useRef<HTMLDivElement | null>(null)
  const {isVisible, isCurrentlyVisible} = useIsVisible({ref})
  const prevIsVisible = useRef<boolean>(false)

  const {
    isFetchingNextPageForSecondaryGroups,
    fetchNextPageForSecondaryGroups,
    hasNextPageForSecondaryGroups,
    hasInitialData,
  } = usePaginatedMemexItemsQuery()

  useEffect(() => {
    const readyForNextPage = shouldFetchNextPage({
      isVisible,
      hasInitialData,
      hasNextPage: hasNextPageForSecondaryGroups,
      isFetchingNextPage: isFetchingNextPageForSecondaryGroups,
      skipFetch: false,
      isCurrentlyVisible,
      prevIsVisible,
    })
    if (readyForNextPage) {
      fetchNextPageForSecondaryGroups()
    }
  }, [
    fetchNextPageForSecondaryGroups,
    hasInitialData,
    hasNextPageForSecondaryGroups,
    isFetchingNextPageForSecondaryGroups,
    isVisible,
    isCurrentlyVisible,
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

type ShouldFetchNextPageOptions = {
  isVisible: boolean
  hasInitialData: boolean
  hasNextPage: boolean
  isFetchingNextPage: boolean
  skipFetch: boolean
  isCurrentlyVisible: () => boolean
  prevIsVisible: React.MutableRefObject<boolean>
}

const shouldFetchNextPage = ({
  isVisible,
  hasInitialData,
  hasNextPage,
  isFetchingNextPage,
  skipFetch = false,
  isCurrentlyVisible,
  prevIsVisible,
}: ShouldFetchNextPageOptions) => {
  const visibilityUnchanged = prevIsVisible.current === isVisible
  prevIsVisible.current = isVisible
  // Only request more data when paginator is visible
  if (!isVisible) return false
  // Don't request more data when the hook consumer opts out
  if (skipFetch) return false
  // Don't request more data when there is no initial data
  if (!hasInitialData) return false
  // Don't request more data when we're already fetching
  if (isFetchingNextPage) return false
  // Don't request more data when there are no more pages
  if (!hasNextPage) return false
  if (visibilityUnchanged) {
    // If we get here, then `isVisible` was true on this render and the previous render.
    // `isVisible` trails actual item visibility by at least one render because
    // the intersection observer records a ref's new BoundingClientRect *after* the
    // view repaints.
    // To avoid unnecessary requests, we use isCurrentlyVisible to check the
    // ref's **current** BoundingClientRect with the intersection observer's
    // root bounds. If they intersect, then the paginator is still visible.
    return isCurrentlyVisible()
  }
  // No gates were tripped, so we can request more data
  return true
}

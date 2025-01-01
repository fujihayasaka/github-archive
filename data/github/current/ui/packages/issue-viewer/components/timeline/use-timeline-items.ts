import {isFeatureEnabled} from '@github-ui/feature-flags'
import {getHighlightedEvent} from '@github-ui/timeline-items/HighlightedEvent'
import {useEffect, useMemo, useState} from 'react'
import {graphql, readInlineData, usePaginationFragment} from 'react-relay'
import {rollupEvents} from '../../utils/timeline-rollups'
import type {IssueTimelineIssueFragment$data} from './__generated__/IssueTimelineIssueFragment.graphql'
import type {IssueTimelineItem$data, IssueTimelineItem$key} from './__generated__/IssueTimelineItem.graphql'
import type {NewTimelinePaginationBackQuery} from './__generated__/NewTimelinePaginationBackQuery.graphql'
import type {NewTimelinePaginationFrontQuery} from './__generated__/NewTimelinePaginationFrontQuery.graphql'
import type {useTimelineHighlightItems$data} from './__generated__/useTimelineHighlightItems.graphql'
import type {
  useTimelineItemsBackFragment$data,
  useTimelineItemsBackFragment$key,
} from './__generated__/useTimelineItemsBackFragment.graphql'
import type {
  useTimelineItemsFrontFragment$data,
  useTimelineItemsFrontFragment$key,
} from './__generated__/useTimelineItemsFrontFragment.graphql'
import type {TimelineItem} from './IssueTimeline'
import {TimelineItemFragment} from './IssueTimelineItem'
import {isEventHighlighted, useTimelineHighlights} from './use-timeline-highlight'

type TimelineCounters = {
  frontItems: number
  highlightItems: number
  highlightStartPosition: number
  backItems: number
}

type UseTimelineItemsProps = {
  timelineData: IssueTimelineIssueFragment$data
  highlightedEvent: string | undefined
}

type TimelineNode = NonNullable<
  NonNullable<NonNullable<useTimelineItemsFrontFragment$data['frontTimelineItems']['edges']>[0]>['node']
>

const frontTimelineItemsFragment = graphql`
  fragment useTimelineItemsFrontFragment on Issue
  @argumentDefinitions(count: {type: "Int"}, cursor: {type: "String"})
  @refetchable(queryName: "NewTimelinePaginationFrontQuery") {
    frontTimelineItems: timelineItems(
      first: $count
      visibleEventsOnly: true
      after: $cursor
      includeIssueTypeEvents: true
    ) @defer(label: "Issue__frontTimelineItems") @connection(key: "Issue__frontTimelineItems") {
      pageInfo {
        hasNextPage
      }
      totalCount
      edges {
        node {
          __id
          ...IssueTimelineItem
        }
      }
    }
  }
`

const backTimelineItemsFragment = graphql`
  fragment useTimelineItemsBackFragment on Issue
  @argumentDefinitions(count: {type: "Int"}, cursor: {type: "String"})
  @refetchable(queryName: "NewTimelinePaginationBackQuery") {
    backTimelineItems: timelineItems(
      last: $count
      visibleEventsOnly: true
      before: $cursor
      includeIssueTypeEvents: true
    ) @defer(label: "Issue__backTimelineItems") @connection(key: "Issue__backTimelineItems") {
      pageInfo {
        hasPreviousPage
      }
      totalCount
      edges {
        node {
          __id
          ...IssueTimelineItem
        }
      }
    }
  }
`

// This hook is responsible for combining the front, highlight, and back items into a single list (including the 'load more' sections)
export const useTimelineItems = ({timelineData, highlightedEvent}: UseTimelineItemsProps) => {
  // This object is responsible for keeping track of the positioning and number of items in each section of the timeline.
  // That state depends on responses from the server but also user actions, so we aggregate the data here.
  const [timelineCounters, setTimelineCounters] = useState<TimelineCounters>({
    frontItems: 0,
    highlightItems: 0,
    highlightStartPosition: 0,
    backItems: 0,
  })

  // These are used to ensure that the fix for https://github.com/github/issues/issues/13005 is only applied once
  const [frontRefetched, setFrontRefetched] = useState(false)
  const [backRefetched, setBackRefetched] = useState(false)
  // This state is used to determine if the highlighted event has been fetched to prevent reloading if
  // a user clicks a comment link more than once in succession.
  // We reset this state when the highlighted event changes.
  const [fetched, setFetched] = useState(false)
  // This state is used to determine if the user has clicked on a different highlighted event
  const [lastFetchedHighlight, setLastFetchedHighlight] = useState<string | null>(null)
  const [lastTotalBeforeFocus, setLastTotalBeforeFocus] = useState<number | null>(null)
  const [shouldLoadBackItems, setShouldLoadBackItems] = useState(false)
  const [loadingInitialBackItems, setLoadingInitialBackItems] = useState(false)

  const {
    data: {frontTimelineItems: frontTimelineData},
    loadNext: loadMoreFrontItems,
    refetch: refetchFrontItems,
  } = usePaginationFragment<NewTimelinePaginationFrontQuery, useTimelineItemsFrontFragment$key>(
    frontTimelineItemsFragment,
    timelineData,
  )
  const {
    data: {backTimelineItems: backTimelineData},
    loadPrevious: loadMoreBackItems,
    refetch: refetchBackItems,
  } = usePaginationFragment<NewTimelinePaginationBackQuery, useTimelineItemsBackFragment$key>(
    backTimelineItemsFragment,
    timelineData,
  )

  const totalItemCount = frontTimelineData?.totalCount ?? 0

  const {items: frontItems} = mapAndFilterTimelineItems(frontTimelineData)
  const {items: backItems} = mapAndFilterTimelineItems(backTimelineData)
  const hasFrontTimelineData = !!frontTimelineData
  const isCacheFixWorkaroundEnabled = isFeatureEnabled('issues_react_cache_fix_workaround')
  useEffect(() => {
    if (!hasFrontTimelineData) {
      if (isCacheFixWorkaroundEnabled && !frontRefetched) {
        setFrontRefetched(true)
        refetchFrontItems({}, {fetchPolicy: 'network-only'})
      } else {
        throw new Error(
          `Missing front timeline items for issue ${timelineData.id}.  After refetching, the frontTimelineItems should be defined.`,
        )
      }
    }
  }, [frontRefetched, hasFrontTimelineData, isCacheFixWorkaroundEnabled, refetchFrontItems, timelineData.id])

  const hasBackTimelineData = !!backTimelineData
  useEffect(() => {
    if (!hasBackTimelineData) {
      if (isCacheFixWorkaroundEnabled && !backRefetched) {
        setBackRefetched(true)
        refetchBackItems({}, {fetchPolicy: 'network-only'})
      } else {
        throw new Error(
          `Missing back timeline items for issue ${timelineData.id}.  After refetching, the backTimelineItems should be defined.`,
        )
      }
    }
  }, [backRefetched, hasBackTimelineData, isCacheFixWorkaroundEnabled, refetchBackItems, timelineData.id])

  const highlight = useMemo(() => getHighlightedEvent(highlightedEvent), [highlightedEvent])
  // This means that the highlighted item is already in the front or back items so no need to go back to the server
  const highlightIsPreloaded = useMemo(
    () => (highlight ? [...frontItems, ...backItems].some(event => isEventHighlighted(event, highlight)) : false),
    [backItems, frontItems, highlight],
  )

  useEffect(() => {
    if (backItems.length === 0) {
      setShouldLoadBackItems(true)
    }
  }, [backItems.length])

  useEffect(() => {
    if (shouldLoadBackItems) {
      const backItemsToFetch = Math.min(15, totalItemCount - frontItems.length)
      if (backItemsToFetch > 0) {
        setLoadingInitialBackItems(true)
        loadMoreBackItems(backItemsToFetch, {
          onComplete: () => {
            setShouldLoadBackItems(false)
            setLoadingInitialBackItems(false)
          },
        })
      }
    }
  }, [frontItems.length, loadMoreBackItems, shouldLoadBackItems, totalItemCount])

  const {
    data: highlightData,
    loadPrevious: loadBeforeHighlight,
    totalBeforeFocus,
    loadNext: loadAfterHighlight,
  } = useTimelineHighlights(timelineData.id, highlight, !fetched && highlight && !highlightIsPreloaded)

  useEffect(() => {
    setLastTotalBeforeFocus(totalBeforeFocus)
  }, [totalBeforeFocus])

  const loadedHighlightItems = useMemo(() => {
    if (highlightData) {
      const {items: highlightItems} = mapAndFilterTimelineItems(highlightData)
      return highlightItems
    }
    return []
  }, [highlightData])

  useEffect(() => {
    if (highlightData) {
      if (highlightedEvent) {
        setFetched(!(lastFetchedHighlight && highlightedEvent !== lastFetchedHighlight))
        setLastFetchedHighlight(highlightedEvent)
      }
    }
  }, [highlight, highlightData, highlightedEvent, lastFetchedHighlight])

  const hasLazyLoadedHighlights = loadedHighlightItems.length > 0

  const itemsRemainingFront = Math.max(
    hasLazyLoadedHighlights
      ? timelineCounters.highlightStartPosition - timelineCounters.frontItems
      : totalItemCount - frontItems.length - backItems.length,
    0,
  )

  const itemsRemainingBack = Math.max(
    hasLazyLoadedHighlights
      ? totalItemCount -
          (timelineCounters.highlightStartPosition + timelineCounters.highlightItems) -
          timelineCounters.backItems
      : totalItemCount - frontItems.length - backItems.length,
    0,
  )

  // If a highlighted event (or its neighbor) exists in the front or back items, we need to remove it from the loaded highlight items
  const uniqueLoadedHighlightItems = useMemo(() => {
    if (hasLazyLoadedHighlights) {
      return subtractItems(loadedHighlightItems, [...frontItems, ...backItems])
    }
    return []
  }, [frontItems, backItems, loadedHighlightItems, hasLazyLoadedHighlights])

  const timelineItems: TimelineItem[] | null = useMemo(() => {
    // If we dont have the same number of items as the server says we should have, we should return null since we are missing some data
    if (frontItems.length === 0 && totalItemCount !== 0) {
      return null
    }

    // If we loaded duplicated records from the front and back load, we dedupe them to prevent accidental duplicates
    //
    // This can happen if for some reason we get more items than there is in the issue
    // like when an event is deleted or a mismatch from live updates
    if (frontItems.length + uniqueLoadedHighlightItems.length + backItems.length >= totalItemCount) {
      return rollupEvents(dedupeItems([...frontItems, ...uniqueLoadedHighlightItems, ...backItems])).map(item => ({
        type: 'event',
        ...item,
      }))
    }
    // Otherwise we render both arrays and inject the load buttons in the middle

    const frontTimelineItems: TimelineItem[] = rollupEvents(frontItems).map(item => ({
      type: 'event',
      ...item,
    }))

    const loadMoreFront: TimelineItem[] =
      itemsRemainingFront === 0
        ? []
        : [
            {
              type: 'load',
              position: 'top',
              loadFromTop: loadMoreFrontItems,
              loadFromBottom: (count, options) => {
                if (hasLazyLoadedHighlights) {
                  loadBeforeHighlight(count, options)
                } else {
                  loadMoreBackItems(count, options)
                }
              },
              numberOfRemainingItems: itemsRemainingFront,
              isCurrentlyLoading: loadingInitialBackItems && uniqueLoadedHighlightItems.length === 0,
            },
          ]

    const highlightTimelineItems: TimelineItem[] = !hasLazyLoadedHighlights
      ? []
      : rollupEvents(uniqueLoadedHighlightItems).map(item => ({
          type: 'event',
          ...item,
        }))

    const loadMoreBack: TimelineItem[] =
      !hasLazyLoadedHighlights || itemsRemainingBack === 0
        ? []
        : [
            {
              type: 'load',
              position: 'bottom',
              loadFromTop: loadAfterHighlight,
              loadFromBottom: loadMoreBackItems,
              numberOfRemainingItems: itemsRemainingBack,
              isCurrentlyLoading: loadingInitialBackItems && uniqueLoadedHighlightItems.length > 0,
            },
          ]

    const backTimelineItems: TimelineItem[] = rollupEvents(backItems).map(item => ({
      type: 'event',
      ...item,
    }))

    return [...frontTimelineItems, ...loadMoreFront, ...highlightTimelineItems, ...loadMoreBack, ...backTimelineItems]
  }, [
    frontItems,
    uniqueLoadedHighlightItems,
    backItems,
    totalItemCount,
    itemsRemainingFront,
    loadMoreFrontItems,
    loadingInitialBackItems,
    hasLazyLoadedHighlights,
    itemsRemainingBack,
    loadAfterHighlight,
    loadMoreBackItems,
    loadBeforeHighlight,
  ])

  useEffect(() => {
    if (
      timelineCounters.frontItems !== frontItems.length ||
      timelineCounters.backItems !== backItems.length ||
      timelineCounters.highlightItems !== uniqueLoadedHighlightItems.length ||
      lastTotalBeforeFocus !== totalBeforeFocus
    ) {
      setTimelineCounters(current => {
        return {
          frontItems: frontItems.length,
          backItems: backItems.length,
          highlightItems: uniqueLoadedHighlightItems.length,
          // This is required since in pagination requests the server will always return 'totalBeforeFocus: 0' even if we do have a highlighted item
          highlightStartPosition: totalBeforeFocus > 0 ? totalBeforeFocus : current.highlightStartPosition,
        }
      })
    }
  }, [
    frontItems,
    backItems,
    uniqueLoadedHighlightItems,
    totalBeforeFocus,
    timelineCounters.frontItems,
    timelineCounters.backItems,
    timelineCounters.highlightItems,
    lastTotalBeforeFocus,
  ])

  const highlightedReady = isHighlightReady(totalItemCount, backItems.length, timelineCounters, highlightIsPreloaded)

  return {timelineItems, totalItemCount, highlightedReady}
}

function isHighlightReady(
  totalItemCount: number,
  backItems: number,
  timelineCounters: TimelineCounters,
  highlightIsPreloaded: boolean,
) {
  // No highlighted item
  if (timelineCounters.highlightItems === 0 && !highlightIsPreloaded) return false

  const highlightedItemsInBack =
    timelineCounters.highlightStartPosition + timelineCounters.highlightItems > totalItemCount - 15
  const backItemsPending = totalItemCount > 15 && backItems === 0

  // Delay scrolling if the higlighted items overlap with the back items, and they aren't ready yet
  if (highlightedItemsInBack && backItemsPending) return false

  return true
}

/**
 * Takes a list of timeline items and dedupes them based on their __id
 */
const dedupeItems = (items: IssueTimelineItem$data[]) =>
  items.reduce(
    ({keys, values}, item) => {
      if (!keys.has(item.__id)) {
        keys.add(item.__id)
        values.push(item)
      }

      return {keys, values}
    },
    {keys: new Set<string>(), values: [] as IssueTimelineItem$data[]},
  ).values

/**
 * Takes two lists of timeline items and subtracts the second list from the first based on their __id
 */
const subtractItems = (items: IssueTimelineItem$data[], subtract: IssueTimelineItem$data[]) =>
  items.filter(item => !subtract.some(subtractItem => subtractItem.__id === item.__id))

const mapAndFilterTimelineItems = (
  timelineData:
    | useTimelineItemsFrontFragment$data['frontTimelineItems']
    | useTimelineItemsBackFragment$data['backTimelineItems']
    | useTimelineHighlightItems$data['timelineItems']
    | undefined,
) => {
  if (!timelineData) {
    return {items: []}
  }
  const timelineItems = (timelineData.edges || [])
    .reduce((items, item) => {
      if (item?.node?.__id) items.push(item.node)

      return items
    }, [] as TimelineNode[])
    .map(item => {
      // eslint-disable-next-line no-restricted-syntax
      return readInlineData<IssueTimelineItem$key>(TimelineItemFragment, item)
    })

  return {items: timelineItems}
}

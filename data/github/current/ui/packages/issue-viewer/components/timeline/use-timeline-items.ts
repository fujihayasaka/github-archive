import {rollupEvents} from '../../utils/timeline-rollups'
import {useEffect, useMemo, useState} from 'react'
import type {NewIssueTimelineItem$data, NewIssueTimelineItem$key} from './__generated__/NewIssueTimelineItem.graphql'
import type {TimelineItem} from './NewIssueTimeline'
import {graphql, readInlineData, usePaginationFragment, type RefetchFnDynamic} from 'react-relay'
import type {NewTimelinePaginationFrontQuery} from './__generated__/NewTimelinePaginationFrontQuery.graphql'
import type {NewTimelinePaginationBackQuery} from './__generated__/NewTimelinePaginationBackQuery.graphql'
import {getHighlightedEvent} from '@github-ui/timeline-items/HighlightedEvent'
import {isEventHighlighted, useTimelineHighlights} from './use-timeline-highlight'
import type {useTimelineHighlightItems$data} from './__generated__/useTimelineHighlightItems.graphql'
import {TimelineItemFragment} from './NewIssueTimelineItem'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import type {NewIssueTimelineIssueFragment$data} from './__generated__/NewIssueTimelineIssueFragment.graphql'
import type {
  useTimelineItemsFrontFragment$data,
  useTimelineItemsFrontFragment$key,
} from './__generated__/useTimelineItemsFrontFragment.graphql'
import type {
  useTimelineItemsBackFragment$data,
  useTimelineItemsBackFragment$key,
} from './__generated__/useTimelineItemsBackFragment.graphql'

type TimelineCounters = {
  frontItems: number
  highlightItems: number
  highlightStartPosition: number
  backItems: number
}

type UseTimelineItemsProps = {
  timelineData: NewIssueTimelineIssueFragment$data
  highlightedEvent: string | undefined
}

type TimelineNode = NonNullable<
  NonNullable<NonNullable<useTimelineItemsFrontFragment$data['frontTimelineItems']['edges']>[0]>['node']
>

const frontTimelineItemsFragment = graphql`
  fragment useTimelineItemsFrontFragment on Issue
  @argumentDefinitions(count: {type: "Int"}, cursor: {type: "String"})
  @refetchable(queryName: "NewTimelinePaginationFrontQuery") {
    frontTimelineItems: timelineItems(first: $count, visibleEventsOnly: true, after: $cursor)
      @defer(label: "Issue__frontTimelineItems")
      @connection(key: "Issue__frontTimelineItems") {
      pageInfo {
        hasNextPage
      }
      totalCount
      edges {
        node {
          __id
          ...NewIssueTimelineItem
        }
      }
    }
  }
`

const backTimelineItemsFragment = graphql`
  fragment useTimelineItemsBackFragment on Issue
  @argumentDefinitions(count: {type: "Int"}, cursor: {type: "String"})
  @refetchable(queryName: "NewTimelinePaginationBackQuery") {
    backTimelineItems: timelineItems(last: $count, visibleEventsOnly: true, before: $cursor)
      @defer(label: "Issue__backTimelineItems")
      @connection(key: "Issue__backTimelineItems") {
      pageInfo {
        hasPreviousPage
      }
      totalCount
      edges {
        node {
          __id
          ...NewIssueTimelineItem
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

  const frontItems = mapAndFilterTimelineItems(frontTimelineData, refetchFrontItems, frontRefetched, setFrontRefetched)
  const backItems = mapAndFilterTimelineItems(backTimelineData, refetchBackItems, backRefetched, setBackRefetched)

  const highlight = useMemo(() => getHighlightedEvent(highlightedEvent), [highlightedEvent])
  // This means that the highlighted item is already in the front or back items so no need to go back to the server
  const highlightIsPreloaded = useMemo(
    () => (highlight ? [...frontItems, ...backItems].some(event => isEventHighlighted(event, highlight)) : false),
    [backItems, frontItems, highlight],
  )

  const {
    data: highlightData,
    loadPrevious: loadBeforeHighlight,
    totalBeforeFocus,
    loadNext: loadAfterHighlight,
  } = useTimelineHighlights(timelineData.id, highlight, !fetched && highlight && !highlightIsPreloaded)

  useEffect(() => {
    setLastTotalBeforeFocus(totalBeforeFocus)
  }, [totalBeforeFocus])

  const loadedHighlightItems = useMemo(
    () => (highlightData ? mapAndFilterTimelineItems(highlightData) : []),

    [highlightData],
  )

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

  const timelineItems: TimelineItem[] = useMemo(() => {
    // If we loaded duplicated records from the front and back load, we dedupe them to prevent accidental duplicates
    //
    // This can happen if for some reason we get more items than there is in the issue
    // like when an event is deleted or a mismatch from live updates
    if (frontItems.length + loadedHighlightItems.length + backItems.length >= totalItemCount) {
      return rollupEvents(dedupeItems([...frontItems, ...loadedHighlightItems, ...backItems])).map(item => ({
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
            },
          ]

    const backTimelineItems: TimelineItem[] = rollupEvents(backItems).map(item => ({
      type: 'event',
      ...item,
    }))

    return [...frontTimelineItems, ...loadMoreFront, ...highlightTimelineItems, ...loadMoreBack, ...backTimelineItems]
  }, [
    frontItems,
    loadedHighlightItems,
    backItems,
    totalItemCount,
    itemsRemainingFront,
    hasLazyLoadedHighlights,
    loadMoreFrontItems,
    loadBeforeHighlight,
    loadMoreBackItems,
    uniqueLoadedHighlightItems,
    itemsRemainingBack,
    loadAfterHighlight,
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

  return {timelineItems, totalItemCount}
}

/**
 * Takes a list of timeline items and dedupes them based on their __id
 */
const dedupeItems = (items: NewIssueTimelineItem$data[]) =>
  items.reduce(
    ({keys, values}, item) => {
      if (!keys.has(item.__id)) {
        keys.add(item.__id)
        values.push(item)
      }

      return {keys, values}
    },
    {keys: new Set<string>(), values: [] as NewIssueTimelineItem$data[]},
  ).values

/**
 * Takes two lists of timeline items and subtracts the second list from the first based on their __id
 */
const subtractItems = (items: NewIssueTimelineItem$data[], subtract: NewIssueTimelineItem$data[]) =>
  items.filter(item => !subtract.some(subtractItem => subtractItem.__id === item.__id))

const mapAndFilterTimelineItems = (
  timelineData:
    | useTimelineItemsFrontFragment$data['frontTimelineItems']
    | useTimelineItemsBackFragment$data['backTimelineItems']
    | useTimelineHighlightItems$data['timelineItems']
    | undefined,
  refetch?: RefetchFnDynamic<
    NewTimelinePaginationFrontQuery | NewTimelinePaginationBackQuery,
    useTimelineItemsFrontFragment$key | useTimelineItemsBackFragment$key
  >,
  refetched?: boolean,
  setRefetched?: (value: boolean) => void,
) => {
  const isCacheFixWorkaroundEnabled = isFeatureEnabled('issues_react_cache_fix_workaround')

  if (!timelineData) {
    // Workaround until we find a way to fix an issue where the data is null when we have the data in the browser cache
    // but it's marked as stale by Relay. See https://github.com/github/issues/issues/13005
    if (refetch !== undefined && !refetched && setRefetched !== undefined && isCacheFixWorkaroundEnabled) {
      refetch({}, {fetchPolicy: 'network-only', onComplete: () => setRefetched(true)})
    }
    return []
  }
  return (timelineData.edges || [])
    .reduce((items, item) => {
      if (item?.node?.__id) items.push(item.node)

      return items
    }, [] as TimelineNode[])
    .map(item => {
      return readInlineData<NewIssueTimelineItem$key>(TimelineItemFragment, item)
    })
}

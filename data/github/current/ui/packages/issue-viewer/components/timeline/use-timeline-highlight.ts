import {getHighlightedEvent, type HighlightedEvent} from '@github-ui/timeline-items/HighlightedEvent'
import type {IssueTimelineItem$data} from './__generated__/IssueTimelineItem.graphql'
import {graphql, useLazyLoadQuery, usePaginationFragment, type LoadMoreFn} from 'react-relay'
import type {useTimelineHighlightQuery} from './__generated__/useTimelineHighlightQuery.graphql'
import type {
  useTimelineHighlightItems$data,
  useTimelineHighlightItems$key,
} from './__generated__/useTimelineHighlightItems.graphql'
import type {NewTimelinePaginationHighlightQuery} from './__generated__/NewTimelinePaginationHighlightQuery.graphql'

export const isEventHighlighted = (item: IssueTimelineItem$data, highlight: HighlightedEvent) => {
  // Discard id mismatches
  if (String(item.databaseId) !== highlight.id) return false

  // Discard issue comment highlights if the item is not an issue comment
  if (highlight.prefix === 'issuecomment' && item.__typename !== 'IssueComment') return false

  return true
}

export type HighlightedData = {
  data: useTimelineHighlightItems$data['timelineItems'] | undefined

  hasPrevious: boolean
  totalBeforeFocus: number
  loadPrevious: LoadMoreFn<NewTimelinePaginationHighlightQuery>

  hasNext: boolean
  totalAfterFocus: number
  loadNext: LoadMoreFn<NewTimelinePaginationHighlightQuery>
}

export const getHighlight = (events: IssueTimelineItem$data[], highlightedEvent: string | undefined) => {
  const highlight = getHighlightedEvent(highlightedEvent)

  const highlightedItem = highlight && events.find(item => isEventHighlighted(item, highlight))

  return {
    highlight,
    isEventLoaded: highlightedItem !== undefined,
  }
}

export const useTimelineHighlights = (
  issueId: string,
  highlightedEvent: HighlightedEvent | undefined,
  fetchFromServer: boolean = false,
): HighlightedData => {
  const highlightText = highlightedEvent ? `${highlightedEvent.prefix}-${highlightedEvent.id}` : ''
  const {node} = useLazyLoadQuery<useTimelineHighlightQuery>(
    graphql`
      query useTimelineHighlightQuery(
        $id: ID!
        $focusText: String!
        $after: String
        $before: String
        $first: Int!
        $last: Int
        $focusNeighborCount: Int
      ) {
        node(id: $id) {
          ... on Issue {
            ...useTimelineHighlightItems
              @dangerously_unaliased_fixme
              @arguments(
                after: $after
                first: $first
                focusText: $focusText
                last: $last
                before: $before
                focusNeighborCount: $focusNeighborCount
              )
          }
        }
      }
    `,
    {id: issueId, focusText: highlightText, first: 1, focusNeighborCount: 3},
    // Past Andre: I don't really like that to conform to no conditional hooks, we have to force fetch from the store
    // to avoid a query, as otherwise we always fetch the highlights from the server.
    // Maybe a valid place to use fetchQuery? How would this work with pagination though?
    // To be continued...
    {fetchPolicy: fetchFromServer ? 'network-only' : 'store-only'},
  )

  const {data, hasNext, hasPrevious, loadNext, loadPrevious} = usePaginationFragment<
    NewTimelinePaginationHighlightQuery,
    useTimelineHighlightItems$key
  >(
    graphql`
      fragment useTimelineHighlightItems on Issue
      @argumentDefinitions(
        after: {type: "String"}
        first: {type: "Int"}
        before: {type: "String"}
        last: {type: "Int"}
        focusText: {type: "String"}
        focusNeighborCount: {type: "Int"}
      )
      @refetchable(queryName: "NewTimelinePaginationHighlightQuery") {
        timelineItems(
          first: $first
          after: $after
          before: $before
          last: $last
          focusText: $focusText
          visibleEventsOnly: true
          focusNeighborCount: $focusNeighborCount
        ) @connection(key: "timelineBackwards_timelineItems", filters: []) {
          beforeFocusCount
          afterFocusCount
          # Used in the timeline rollup
          # eslint-disable-next-line relay/unused-fields
          edges {
            node {
              __id
              # Used in the timeline component
              # eslint-disable-next-line relay/must-colocate-fragment-spreads
              ...IssueTimelineItem
            }
          }
        }
      }
    `,
    node,
  )

  const totalBeforeFocus = data?.timelineItems?.beforeFocusCount || 0
  const totalAfterFocus = data?.timelineItems?.afterFocusCount || 0

  return {
    data: data?.timelineItems,
    hasPrevious,
    totalBeforeFocus,
    loadPrevious,
    hasNext,
    totalAfterFocus,
    loadNext,
  }
}

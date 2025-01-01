import {graphql, useFragment} from 'react-relay'
import type {IssueTimelineItem$data} from './__generated__/IssueTimelineItem.graphql'
import {useEffect, useMemo, useRef, useState, type ReactNode} from 'react'
import {Box, Timeline} from '@primer/react'
import type {IssueTimelineIssueFragment$key} from './__generated__/IssueTimelineIssueFragment.graphql'
import type {IssueViewerIssue$data} from '../__generated__/IssueViewerIssue.graphql'
import {useIssueViewerSubscription} from '../IssueViewerSubscription'
import {LABELS} from '@github-ui/timeline-items/Labels'
import type {RolledUpTimelineItem} from '../../utils/timeline-rollups'
import {LoadMore, type LoadMoreCallbackFn} from './LoadMore'
import {isEventHighlighted} from './use-timeline-highlight'
import {FailedLoadTimelineItem} from './FailedLoadTimelineItem'
import {TimelineTransferringFlash} from './TimelineTransferringFlash'
import {getHighlightedEvent} from '@github-ui/timeline-items/HighlightedEvent'
import {useNewScrollToHighlighted} from '../../hooks/use-scroll-to-highlighted'
// Using getFocusableChild for a callback after client side loading, won't affect SSR
// eslint-disable-next-line no-restricted-imports
import {getFocusableChild} from '@primer/behaviors/utils'
import {VALUES} from '@github-ui/timeline-items/Values'

import {wrapElement} from '@github-ui/timeline-items/LayoutHelpers'

import {useTimelineItems} from './use-timeline-items'
import {TEST_IDS} from '../../constants/test-ids'
import type {IssueTimelineSecondary$key} from './__generated__/IssueTimelineSecondary.graphql'
import {IssueTimelineItem, type EventProps} from './IssueTimelineItem'

type LoadItem = {
  type: 'load'
  position: 'top' | 'bottom'
  loadFromTop: LoadMoreCallbackFn
  loadFromBottom: LoadMoreCallbackFn
  numberOfRemainingItems: number
  isCurrentlyLoading?: boolean
}

type EventItem = {type: 'event'} & RolledUpTimelineItem<IssueTimelineItem$data>
export type TimelineItem = EventItem | LoadItem

/**
 * Temporary type for parsing the timeline items and grouping them into section elements
 * for improve the accessibility of the event items by adding landmarks for navigation.
 */
type RenderItem = {
  /**
   * Controls whether the item has already been added to the grouped events or not.
   *
   * Only used in events and not in load items, graceful degratation items or issue comments.
   */
  isAddedToGroupedEvents: boolean
  timelineItem: TimelineItem
  render: ReactNode
}

const mainTimelineFragment = graphql`
  fragment IssueTimelineIssueFragment on Issue {
    id
    url
    repository {
      id
      nameWithOwner
    }
    ...useTimelineItemsFrontFragment @arguments(count: 15)
    ...useTimelineItemsBackFragment @arguments(count: 0)
  }
`

type IssueTimelineLiveUpdatesLoaderProps = {
  issueId: string
  itemCount: number
}
const IssueTimelineLiveUpdatesLoader = ({issueId, itemCount}: IssueTimelineLiveUpdatesLoaderProps) => {
  useIssueViewerSubscription(issueId, itemCount, 'Issue__backTimelineItems')
  return null
}

type IssueTimelineProps = {
  issue: IssueViewerIssue$data
  issueSecondary: IssueTimelineSecondary$key | undefined
  highlightedEvent: string | undefined
} & EventProps
export const IssueTimeline = ({
  issue,
  issueSecondary,
  viewer,
  highlightedEvent,
  onCommentChange,
  onCommentReply,
  onCommentEditCancel,
  optionConfig,
}: IssueTimelineProps) => {
  const data = useFragment<IssueTimelineIssueFragment$key>(mainTimelineFragment, issue)
  const secondaryData = useFragment(
    graphql`
      fragment IssueTimelineSecondary on Issue {
        isTransferInProgress
      }
    `,
    issueSecondary,
  )

  const highlight = useMemo(() => getHighlightedEvent(highlightedEvent), [highlightedEvent])

  // This state controls if the highlight borders should be shown or not
  const [shouldHighlightElement, setShouldHighlightElement] = useState<boolean>(highlight !== undefined)

  // After rendering, clicking anywhere should remove the borders
  useEffect(() => {
    const handlePageClick = () => {
      setShouldHighlightElement(false)
    }
    document.addEventListener('click', handlePageClick)

    return () => {
      document.removeEventListener('click', handlePageClick)
    }
  }, [highlight])

  // If a new element's link is clicked, we should restore the highlight
  useEffect(() => {
    if (!highlight?.id) return

    setShouldHighlightElement(true)
  }, [highlight?.id])

  const {timelineItems, totalItemCount, highlightedReady} = useTimelineItems({
    timelineData: data,
    highlightedEvent,
  })

  // Iterate items to check if the loaded highlight is in the list
  // Room for performance optimization if we face issues in large timelines, as we can determine
  // if the highlighted item is already present during the mapping process.
  // https://github.com/github/github/blob/9ecd32f60f96a519f99462c48f6235d5842ca814/ui/packages/issue-viewer/components/timeline/IssueTimeline.tsx#L249
  const highlightedItemRef = useRef<HTMLDivElement>(null)
  const isHighlightLoaded = useMemo(() => {
    if (!timelineItems) return false
    if (!shouldHighlightElement || !highlight) return false

    return timelineItems.some(item => {
      if (item.type !== 'event' || !item.item) return false

      return isEventHighlighted(item.item, highlight)
    })
  }, [highlight, timelineItems, shouldHighlightElement])

  useNewScrollToHighlighted(isHighlightLoaded, highlightedItemRef, highlightedEvent, highlightedReady)

  const focusFirstLoadedItem = (items: TimelineItem[], currentIndex: number) => {
    // A timeout is needed to trigger the focusing asynchronously
    // so it doesn't happen before Relay loads the new timeline items
    setTimeout(() => {
      // We want to use the previous item as a base, since the load button
      // will get pushed down and/or unmounted, when all items are loaded.
      const baseItem = items[currentIndex - 1]
      if (!baseItem || baseItem.type !== 'event' || !baseItem.item?.__id) return

      // To avoid complex propagation of refs, we instead query via data attributes set
      // in the TimelineRowBorder component and take the next element, which should be
      // the first of the newly loaded events.
      const nextItemSelector = `[${VALUES.timeline.dataWrapperTimelineEventId}="${baseItem.item.__id}"] + *`
      const nextEvent = document.querySelector<HTMLElement>(nextItemSelector)

      let focusTarget: HTMLElement | null | undefined = null

      if (nextEvent) {
        focusTarget = getFocusableChild(nextEvent)
      } else {
        // Handle case where base item is inside a <section> and doesn't have a next sibling (All events that are not comments are grouped inside <section> tags.)
        const baseItemSelector = `[${VALUES.timeline.dataWrapperTimelineEventId}="${baseItem.item.__id}"]`
        const baseElement = document.querySelector<HTMLElement>(baseItemSelector)
        const section = baseElement?.closest('section')
        const isGroupedEvent = baseItem.item.__typename !== 'IssueComment'

        if (section && isGroupedEvent) {
          const nextSibling = section.nextElementSibling as HTMLElement | null
          if (nextSibling) {
            focusTarget = getFocusableChild(nextSibling)
          }
        }
      }

      focusTarget?.focus({preventScroll: true})
    })
  }

  if (!timelineItems) {
    throw new Error(
      `Missing timeline items for issue ${issue.id}.  Total item count: ${totalItemCount}.  Highlighted event: ${highlightedEvent}`,
    )
  }

  return (
    <>
      {optionConfig.withLiveUpdates && Boolean(viewer) && (
        <IssueTimelineLiveUpdatesLoader issueId={issue.id} itemCount={totalItemCount} />
      )}
      {secondaryData?.isTransferInProgress && <TimelineTransferringFlash />}
      <h2 className="sr-only">{LABELS.timeline.header}</h2>
      <Timeline data-testid={TEST_IDS.issueTimelineContainer}>
        {timelineItems
          .map((timelineItem: TimelineItem, index, initialTimelineItems): RenderItem => {
            if (timelineItem.type === 'load') {
              const fullType: 'load-top' | 'load-bottom' = `${timelineItem.type}-${timelineItem.position}`

              const wrappedElement = (
                <Box sx={{flexGrow: 1}}>
                  <LoadMore
                    key={fullType}
                    type={fullType}
                    loadFromTopFn={timelineItem.loadFromTop}
                    loadFromBottomFn={timelineItem.loadFromBottom}
                    numberOfRemainingItems={timelineItem.numberOfRemainingItems}
                    lastItemInTopTimelineIsComment
                    firstItemInBottomTimelineIsComment
                    onLoadAllComplete={() => focusFirstLoadedItem(initialTimelineItems, index)}
                    onLoadFromTopComplete={() => focusFirstLoadedItem(initialTimelineItems, index)}
                    onLoadFromBottomComplete={() => focusFirstLoadedItem(initialTimelineItems, index)}
                    isCurrentlyLoadingBackItems={timelineItem.isCurrentlyLoading}
                  >
                    Load more
                  </LoadMore>
                </Box>
              )

              return {
                isAddedToGroupedEvents: false,
                timelineItem,
                render: wrapElement(wrappedElement, undefined, fullType),
              }
            }

            if (timelineItem.item == null) {
              return {
                isAddedToGroupedEvents: false,
                timelineItem,
                render: <FailedLoadTimelineItem key="failed-load-item" />,
              }
            }

            const addDivider = shouldAddDivider(timelineItems || [], index)

            const isHighlighted =
              shouldHighlightElement && highlight && isEventHighlighted(timelineItem.item, highlight)
            return {
              isAddedToGroupedEvents: false,
              timelineItem,
              render: (
                <IssueTimelineItem
                  key={timelineItem.item.__id}
                  item={timelineItem}
                  issueId={data.id}
                  repositoryId={data.repository.id}
                  repositoryNameWithOwner={data.repository.nameWithOwner}
                  issueUrl={data.url}
                  viewer={viewer}
                  onCommentChange={onCommentChange}
                  onCommentReply={onCommentReply}
                  onCommentEditCancel={onCommentEditCancel}
                  refAttribute={isHighlighted ? highlightedItemRef : undefined}
                  optionConfig={optionConfig}
                  isHighlighted={isHighlighted}
                  addDivider={addDivider}
                />
              ),
            }
          })
          .reduce((newArr, currentItem, currentIndex, allItems) => {
            // This is grouping event items that are rendered next to eachother
            // inside <section> tags for adding the correct landmarks for screenreaders
            //
            // All events that are not comments, will be grouped.
            //
            // https://github.com/github/accessibility/issues/5224#issuecomment-1846919306

            if (currentItem.isAddedToGroupedEvents) return newArr
            if (
              currentItem.timelineItem.type !== 'event' ||
              currentItem.timelineItem.item?.__typename === 'IssueComment'
            ) {
              currentItem.isAddedToGroupedEvents = true
              newArr.push(currentItem.render)
              return newArr
            }

            const endSectionIndex = allItems.findIndex((renderItem, index) => {
              return (
                index > currentIndex &&
                (renderItem.timelineItem.type !== 'event' ||
                  renderItem.timelineItem.item?.__typename === 'IssueComment')
              )
            })
            const sectionElement = (
              <section key={`events-${currentItem.timelineItem.item?.__id}`} aria-label="Events">
                {allItems.slice(currentIndex, endSectionIndex > -1 ? endSectionIndex : undefined).map(item => {
                  item.isAddedToGroupedEvents = true
                  return item.render
                })}
              </section>
            )

            newArr.push(sectionElement)
            return newArr
          }, [] as ReactNode[])}
      </Timeline>
    </>
  )
}

function shouldAddDivider(items: TimelineItem[], index: number) {
  if (index === 0) {
    return true
  }
  if (items[index - 1]?.type === 'load') {
    return false
  }
  const item = items[index]
  const previousItem = items[index - 1]
  if (!item || !previousItem) {
    return false
  }

  if (item.type === 'event' && previousItem.type === 'event') {
    const eventType = item.item?.__typename
    const previousEventType = previousItem.item?.__typename
    if (eventType && previousEventType) {
      const isMajorEvent = VALUES.timeline.majorEventTypes.includes(eventType)
      const previousIsMajorEvent = VALUES.timeline.majorEventTypes.includes(previousEventType)

      if (isMajorEvent === previousIsMajorEvent) {
        if (eventType !== 'IssueComment' && previousEventType !== 'IssueComment') {
          return false
        }
      }
    }
  }

  return true
}

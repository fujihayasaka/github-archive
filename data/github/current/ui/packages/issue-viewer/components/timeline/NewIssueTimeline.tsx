import {graphql, useFragment} from 'react-relay'
import type {NewIssueTimelineItem$data} from './__generated__/NewIssueTimelineItem.graphql'
import {useEffect, useMemo, useRef, useState, type ReactNode} from 'react'
import {Timeline} from '@primer/react'
import type {NewIssueTimelineIssueFragment$key} from './__generated__/NewIssueTimelineIssueFragment.graphql'
import type {IssueViewerIssue$data} from '../__generated__/IssueViewerIssue.graphql'
import {useIssueViewerSubscription} from '../IssueViewerSubscription'
import {LABELS} from '@github-ui/timeline-items/Labels'
import type {RolledUpTimelineItem} from '../../utils/timeline-rollups'
import {LoadMore, type LoadMoreCallbackFn} from './LoadMore'
import {isEventHighlighted} from './use-timeline-highlight'
import {NewIssueTimelineItem, type EventProps} from './NewIssueTimelineItem'
import {FailedLoadTimelineItem} from './FailedLoadTimelineItem'
import {TimelineTransferringFlash} from './TimelineTransferringFlash'
import type {IssueTimelineSecondary$key} from '../__generated__/IssueTimelineSecondary.graphql'
import {getHighlightedEvent} from '@github-ui/timeline-items/HighlightedEvent'
import {useNewScrollToHighlighted} from '../../hooks/use-scroll-to-highlighted'
// Using getFocusableChild for a callback after client side loading, won't affect SSR
// eslint-disable-next-line no-restricted-imports
import {getFocusableChild} from '@primer/behaviors/utils'
import {VALUES} from '@github-ui/timeline-items/Values'

import {useTimelineItems} from './use-timeline-items'
import {TEST_IDS} from '../../constants/test-ids'

type LoadItem = {
  type: 'load'
  position: 'top' | 'bottom'
  loadFromTop: LoadMoreCallbackFn
  loadFromBottom: LoadMoreCallbackFn
  numberOfRemainingItems: number
}

type EventItem = {type: 'event'} & RolledUpTimelineItem<NewIssueTimelineItem$data>
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
  fragment NewIssueTimelineIssueFragment on Issue {
    id
    url
    repository {
      id
    }
    ...useTimelineItemsFrontFragment @arguments(count: 15)
    ...useTimelineItemsBackFragment @arguments(count: 15)
  }
`

type NewIssueTimelineLiveUpdatesLoaderProps = {
  issueId: string
  itemCount: number
}
const NewIssueTimelineLiveUpdatesLoader = ({issueId, itemCount}: NewIssueTimelineLiveUpdatesLoaderProps) => {
  useIssueViewerSubscription(issueId, itemCount, 'Issue__backTimelineItems')
  return null
}

type NewIssueTimelineProps = {
  issue: IssueViewerIssue$data
  issueSecondary: IssueTimelineSecondary$key | undefined
  highlightedEvent: string | undefined
} & EventProps
export const NewIssueTimeline = ({
  issue,
  issueSecondary,
  viewer,
  highlightedEvent,
  onCommentChange,
  onCommentReply,
  onCommentEditCancel,
  optionConfig,
}: NewIssueTimelineProps) => {
  const data = useFragment<NewIssueTimelineIssueFragment$key>(mainTimelineFragment, issue)
  const secondaryData = useFragment(
    graphql`
      fragment NewIssueTimelineSecondary on Issue {
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

  const {timelineItems, totalItemCount} = useTimelineItems({
    timelineData: data,
    highlightedEvent,
  })

  // Iterate items to check if the loaded highlight is in the list
  // Room for performance optimization if we face issues in large timelines, as we can determine
  // if the highlighted item is already present during the mapping process.
  // https://github.com/github/github/blob/9ecd32f60f96a519f99462c48f6235d5842ca814/ui/packages/issue-viewer/components/timeline/NewIssueTimeline.tsx#L249
  const highlightedItemRef = useRef<HTMLDivElement>(null)
  const isHighlightLoaded = useMemo(() => {
    if (!shouldHighlightElement || !highlight) return false

    return timelineItems.some(item => {
      if (item.type !== 'event' || !item.item) return false

      return isEventHighlighted(item.item, highlight)
    })
  }, [highlight, timelineItems, shouldHighlightElement])

  useNewScrollToHighlighted(isHighlightLoaded, highlightedItemRef, highlightedEvent)

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
      const nextItemSelector = `[${VALUES.timeline.dataTimelineEventId}="${baseItem.item.__id}"] + *`
      const eventElement = document.querySelector<HTMLElement>(nextItemSelector)
      if (!eventElement) return

      const focusableElement = getFocusableChild(eventElement)
      focusableElement?.focus({preventScroll: true})
    })
  }

  return (
    <>
      {optionConfig.withLiveUpdates && Boolean(viewer) && (
        <NewIssueTimelineLiveUpdatesLoader issueId={issue.id} itemCount={totalItemCount} />
      )}
      {secondaryData?.isTransferInProgress && <TimelineTransferringFlash />}
      <h2 className="sr-only">{LABELS.timeline.header}</h2>
      <Timeline data-testid={TEST_IDS.issueTimelineContainer}>
        {timelineItems
          .map((timelineItem: TimelineItem, index, initialTimelineItems): RenderItem => {
            if (timelineItem.type === 'load') {
              const fullType: 'load-top' | 'load-bottom' = `${timelineItem.type}-${timelineItem.position}`
              return {
                isAddedToGroupedEvents: false,
                timelineItem,
                render: (
                  <LoadMore
                    key={fullType}
                    type={fullType}
                    loadFromTopFn={timelineItem.loadFromTop}
                    loadFromBottomFn={timelineItem.loadFromBottom}
                    numberOfRemainingItems={timelineItem.numberOfRemainingItems}
                    lastItemInTopTimelineIsComment
                    firstItemInBottomTimelineIsComment
                    onLoadAllComplete={() => focusFirstLoadedItem(initialTimelineItems, index)}
                  >
                    Load more
                  </LoadMore>
                ),
              }
            }

            if (timelineItem.item == null) {
              return {
                isAddedToGroupedEvents: false,
                timelineItem,
                render: <FailedLoadTimelineItem key="failed-load-item" />,
              }
            }

            const isHighlighted =
              shouldHighlightElement && highlight && isEventHighlighted(timelineItem.item, highlight)
            return {
              isAddedToGroupedEvents: false,
              timelineItem,
              render: (
                <NewIssueTimelineItem
                  key={timelineItem.item.__id}
                  item={timelineItem}
                  issueId={data.id}
                  repositoryId={data.repository.id}
                  issueUrl={data.url}
                  viewer={viewer}
                  onCommentChange={onCommentChange}
                  onCommentReply={onCommentReply}
                  onCommentEditCancel={onCommentEditCancel}
                  refAttribute={isHighlighted ? highlightedItemRef : undefined}
                  optionConfig={optionConfig}
                  isHighlighted={isHighlighted}
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

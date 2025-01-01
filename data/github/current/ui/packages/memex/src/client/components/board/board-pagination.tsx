import {testIdProps} from '@github-ui/test-id-props'
import {Button} from '@primer/react'
import {clsx} from 'clsx'
import {memo, useCallback, useEffect, useMemo, useRef} from 'react'

import type {PageTypeForGroupedItems} from '../../state-providers/memex-items/queries/query-keys'
import {usePaginatedMemexItemsQuery} from '../../state-providers/memex-items/queries/use-paginated-memex-items-query'
import {StyledGroupHeader} from '../common/group/styled-group-header'
import {TextPlaceholder} from '../common/placeholders'
import {
  useGroupsVisiblePagination,
  useSecondaryGroupsVisiblePagination,
  useSinglyGroupedItemsVisiblePagination,
} from '../common/use-visible-pagination'
import styles from './board-pagination.module.css'
import {CardBaseWithSash} from './card/card-base-with-sash'
import {ColumnFrame} from './column/column-frame'
import type {ColumnHeaderType} from './column/types'
import useIsVisible from './hooks/use-is-visible'

export const PLACEHOLDER_CARD_COUNT = 5
const PLACEHOLDER_COLUMN_COUNT = 5

/** Paginator for vertical groups (i.e., columns) */
export const ColumnsPagination: React.FC<{headerType?: ColumnHeaderType}> = ({headerType = 'visible'}) => {
  // headerType === 'hidden' : columns inside a horizontal swimlane group
  // headerType === 'only' : header columns for a board view with swimlanes
  // headerType === 'visible' : board view columns with no horizontal swimlanes
  const {ref, hasNextPage} = useGroupsVisiblePagination(headerType === 'hidden')
  let placeholder = <PlaceholderColumn headerType={headerType} />
  if (headerType !== 'visible') {
    placeholder = <div className={styles.Box_1}>{placeholder}</div>
  }
  return (
    <div ref={ref} {...testIdProps('board-pagination-vertical')} className={styles.Box}>
      {hasNextPage ? placeholder : null}
    </div>
  )
}

/** Paginator for horizontal groups (i.e., swimlanes) */
export const HorizontalGroupsPagination: React.FC = () => {
  const {ref, hasNextPage} = useSecondaryGroupsVisiblePagination()
  const {queriesForGroups} = usePaginatedMemexItemsQuery()
  let columnCount = queriesForGroups.flatMap(query => query.data?.groups).length
  if (queriesForGroups[queriesForGroups.length - 1]?.data?.pageInfo?.hasNextPage) {
    columnCount += 1
  }
  return (
    <div ref={ref} {...testIdProps('board-pagination-horizontal')}>
      {hasNextPage ? <PlaceholderHorizontalGroup columnCount={columnCount} /> : null}
    </div>
  )
}

/** Paginator for items in a vertical group (column) */
export const ColumnCardsPagination: React.FC<{groupId: string}> = ({groupId}) => {
  const {ref, hasNextPage} = useSinglyGroupedItemsVisiblePagination(groupId)
  return (
    <div ref={ref} {...testIdProps(`board-pagination-${groupId}`)}>
      {hasNextPage ? <PlaceholderCard /> : null}
    </div>
  )
}

/** Paginator for items in a specific "cell", i.e. the intersection of a vertical and horizontal group */
export const CellCardsPagination: React.FC<{
  groupId: string
  secondaryGroupId: string
  loadMoreItemsButtonOnKeyDown: React.KeyboardEventHandler
  isLoadMoreItemsButtonFocused: boolean
}> = ({groupId, secondaryGroupId, loadMoreItemsButtonOnKeyDown, isLoadMoreItemsButtonFocused}) => {
  const ref = useRef<HTMLDivElement | null>(null)
  const {isVisible} = useIsVisible({ref})
  const loadMoreItemsButtonRef = useRef<HTMLButtonElement | null>(null)
  const {
    hasNextPageForGroupedItems,
    isFetchingNextPageForGroupedItems,
    fetchNextPageForGroupedItems,
    hasDataForGroupedItemsBatch,
    isFetchingGroupedItemsBatch,
    fetchGroupedItemsBatch,
  } = usePaginatedMemexItemsQuery()

  const pageType: PageTypeForGroupedItems = useMemo(() => ({groupId, secondaryGroupId}), [groupId, secondaryGroupId])
  const hasNextPage = hasNextPageForGroupedItems(pageType)

  const loadMoreItemsOnClick = useCallback(() => {
    fetchNextPageForGroupedItems(pageType)
  }, [fetchNextPageForGroupedItems, pageType])

  const isFetchingBatch = isFetchingGroupedItemsBatch(groupId, secondaryGroupId)
  const isFetchingNextPage = isFetchingNextPageForGroupedItems(pageType)

  // Load more items in a specific groupedItems cell
  const loadMoreButton = hasNextPage ? (
    <Button
      onClick={loadMoreItemsOnClick}
      disabled={isFetchingNextPage}
      onKeyDown={loadMoreItemsButtonOnKeyDown}
      ref={loadMoreItemsButtonRef}
    >
      Load more items
    </Button>
  ) : null

  if (isVisible && !hasDataForGroupedItemsBatch(groupId, secondaryGroupId)) {
    if (!isFetchingBatch) {
      // Load a batch of groupedItems (i.e. a page of cells)
      fetchGroupedItemsBatch(groupId, secondaryGroupId)
    }
  }

  useEffect(() => {
    if (!isLoadMoreItemsButtonFocused || !loadMoreItemsButtonRef.current) {
      return
    }
    loadMoreItemsButtonRef.current.focus()
    loadMoreItemsButtonRef.current.scrollIntoView({block: 'nearest', inline: 'nearest', behavior: 'smooth'})
  }, [isLoadMoreItemsButtonFocused])

  return (
    <div ref={ref} {...testIdProps(`board-pagination-${groupId}-${secondaryGroupId}`)}>
      {isFetchingNextPage || isFetchingBatch ? <PlaceholderCard /> : null}
      {loadMoreButton}
    </div>
  )
}

const PlaceholderCardUnmemoized: React.FC = () => {
  return (
    <CardBaseWithSash
      {...testIdProps('placeholder-card')}
      className={clsx('board-view-column-card', styles.CardBaseWithSash)}
    >
      {[...Array(PLACEHOLDER_CARD_COUNT).keys()].map(key => (
        <TextPlaceholder style={{height: 8}} key={key} minWidth={80} maxWidth={200} {...testIdProps('placeholder')} />
      ))}
    </CardBaseWithSash>
  )
}

const PlaceholderColumnUnmemoized: React.FC<{headerType?: string}> = ({headerType = 'visible'}) => {
  return (
    <ColumnFrame
      className={clsx(headerType, styles.ColumnFrame)}
      headerContent={
        headerType !== 'hidden' ? (
          <TextPlaceholder
            style={{height: 16, marginTop: 4}}
            minWidth={80}
            maxWidth={200}
            {...testIdProps('placeholder-column-header')}
          />
        ) : null
      }
    >
      {headerType === 'only' ? null : <PlaceholderCard />}
    </ColumnFrame>
  )
}

const PlaceholderHorizontalGroupUnmemoized: React.FC<{columnCount?: number}> = ({
  columnCount = PLACEHOLDER_COLUMN_COUNT,
}) => {
  return (
    <>
      <StyledGroupHeader className={clsx('board', 'sticky')}>
        <TextPlaceholder
          style={{height: 12}}
          minWidth={80}
          maxWidth={200}
          {...testIdProps('placeholder-horizontal-group-header')}
        />
      </StyledGroupHeader>
      <div className={styles.Box_1}>
        {[...Array(columnCount).keys()].map(key => (
          <PlaceholderColumnUnmemoized key={key} headerType={'hidden'} />
        ))}
      </div>
    </>
  )
}

export const PlaceholderCard = memo(PlaceholderCardUnmemoized)
const PlaceholderColumn = memo(PlaceholderColumnUnmemoized)
const PlaceholderHorizontalGroup = memo(PlaceholderHorizontalGroupUnmemoized)

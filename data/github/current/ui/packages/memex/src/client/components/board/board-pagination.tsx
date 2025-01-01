import {testIdProps} from '@github-ui/test-id-props'
import {Box, Button} from '@primer/react'
import {clsx} from 'clsx'
import {memo, useCallback, useEffect, useMemo, useRef} from 'react'

import {
  isPageTypeForGroupedItems,
  type PageTypeForGroupedItems,
  type PageTypeForGroups,
  pageTypeForGroups,
  type PageTypeForSecondaryGroups,
  pageTypeForSecondaryGroups,
} from '../../state-providers/memex-items/queries/query-keys'
import {usePaginatedMemexItemsQuery} from '../../state-providers/memex-items/queries/use-paginated-memex-items-query'
import {StyledGroupHeader} from '../common/group/styled-group-header'
import {TextPlaceholder} from '../common/placeholders'
import {
  useGroupsVisiblePagination,
  useSecondaryGroupsVisiblePagination,
  useSinglyGroupedItemsVisiblePagination,
} from '../common/use-visible-pagination'
import {CardBaseWithSash} from './card/card-base-with-sash'
import {ColumnFrame} from './column/column-frame'
import type {ColumnHeaderType} from './column/types'
import {COLUMN_STYLE, HORIZONTAL_GROUP_CONTAINER_STYLE} from './constants'
import useIsVisible from './hooks/use-is-visible'

export const PLACEHOLDER_CARD_COUNT = 5
const PLACEHOLDER_COLUMN_COUNT = 5

type BoardPaginationProps = {
  // We explicitly want to disallow a page type for ungrouped items as well as a page type for grouped
  // items _with_ a secondary id, as that should just use `CellCardsPagination` directly.
  pageType: PageTypeForGroups | PageTypeForSecondaryGroups | {groupId: string}
}

export const BoardPagination: React.FC<BoardPaginationProps> = ({pageType}) => {
  if (isPageTypeForGroupedItems(pageType)) {
    return <ColumnCardsPagination groupId={pageType.groupId} />
  }
  if (pageType === pageTypeForSecondaryGroups) {
    return <HorizontalGroupsPagination />
  }
  if (pageType === pageTypeForGroups) {
    return <ColumnsPagination />
  }
  return null
}

/** Paginator for vertical groups (i.e., columns) */
export const ColumnsPagination: React.FC<{headerType?: ColumnHeaderType}> = ({headerType = 'visible'}) => {
  // headerType === 'hidden' : columns inside a horizontal swimlane group
  // headerType === 'only' : header columns for a board view with swimlanes
  // headerType === 'visible' : board view columns with no horizontal swimlanes
  const {ref, hasNextPage} = useGroupsVisiblePagination(headerType === 'hidden')
  let placeholder = <PlaceholderColumn headerType={headerType} />
  if (headerType !== 'visible') {
    placeholder = <Box sx={HORIZONTAL_GROUP_CONTAINER_STYLE}>{placeholder}</Box>
  }
  return (
    <Box ref={ref} {...testIdProps('board-pagination-vertical')} sx={{display: 'flex'}}>
      {hasNextPage ? placeholder : null}
    </Box>
  )
}

/** Paginator for horizontal groups (i.e., swimlanes) */
const HorizontalGroupsPagination: React.FC = () => {
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
const ColumnCardsPagination: React.FC<{groupId: string}> = ({groupId}) => {
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
      className="board-view-column-card"
      sx={{
        display: 'flex',
        flexDirection: 'column',
        gap: 2,
        p: 2,
        backgroundColor: 'canvas.overlay',
        borderColor: 'border.default',
        borderStyle: 'solid',
        borderRadius: 2,
        borderWidth: '1px',
      }}
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
      sx={{
        ...COLUMN_STYLE,
        p: 2,
        gap: 2,
      }}
      className={headerType}
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
      <Box sx={HORIZONTAL_GROUP_CONTAINER_STYLE}>
        {[...Array(columnCount).keys()].map(key => (
          <PlaceholderColumnUnmemoized key={key} headerType={'hidden'} />
        ))}
      </Box>
    </>
  )
}

export const PlaceholderCard = memo(PlaceholderCardUnmemoized)
const PlaceholderColumn = memo(PlaceholderColumnUnmemoized)
const PlaceholderHorizontalGroup = memo(PlaceholderHorizontalGroupUnmemoized)

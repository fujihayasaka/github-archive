import {useDndContext, useDroppable} from '@github-ui/drag-and-drop'
import {testIdProps} from '@github-ui/test-id-props'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {PlusIcon} from '@primer/octicons-react'
import {Box, Button, Spinner} from '@primer/react'
import {useQueryClient} from '@tanstack/react-query'
import {clsx} from 'clsx'
import {memo, useCallback, useEffect, useMemo, useRef, useState} from 'react'

import {MemexColumnDataType} from '../../../api/columns/contracts/memex-column'
import {ItemType} from '../../../api/memex-items/item-type'
import {BoardColumnMenuHide} from '../../../api/stats/contracts'
import {useVerticalGroupedBy} from '../../../features/grouping/hooks/use-vertical-grouped-by'
import {getGroupFooterPlaceholder, shouldDisableGroupFooter} from '../../../helpers/board-group-utilities'
import {resetScrollPositionImmediately} from '../../../helpers/scroll-utilities'
import {ViewerPrivileges} from '../../../helpers/viewer-privileges'
import {usePostStats} from '../../../hooks/common/use-post-stats'
import {DROP_TYPE_ATTRIBUTE} from '../../../hooks/drag-and-drop/attributes'
import {useDragWithIds} from '../../../hooks/drag-and-drop/drag-and-drop'
import {useAggregationSettings} from '../../../hooks/use-aggregation-settings'
import useAutoScroll from '../../../hooks/use-auto-scroll'
import {useEnabledFeatures} from '../../../hooks/use-enabled-features'
import {useSortedBy} from '../../../hooks/use-sorted-by'
import {LoadingStates, useViewLoadingState} from '../../../hooks/use-view-loading-state'
import {useViews} from '../../../hooks/use-views'
import {isAnySingleSelectColumnModel} from '../../../models/column-model/guards'
import {hasServerGroupId, type HorizontalGroup} from '../../../models/horizontal-group'
import type {MemexItemModel} from '../../../models/memex-item-model'
import {isSingleSelectOption, type VerticalGroup} from '../../../models/vertical-group'
import {handleKeyboardNavigation, suppressEvents} from '../../../navigation/keyboard'
import type {VerticalGroupColumnData} from '../../../state-providers/columns/use-update-vertical-group'
import type {GroupId} from '../../../state-providers/memex-items/queries/query-keys'
import {getServerGroupIdForVerticalGroupId} from '../../../state-providers/memex-items/query-client-api/memex-groups'
import {Resources} from '../../../strings'
import {AggregateLabels} from '../../common/aggregate-labels'
import {GroupMenu} from '../../common/group-menu'
import {SanitizedHtml} from '../../dom/sanitized-html'
import {CurrentIterationLabel} from '../../fields/iteration/iteration-label'
import {SingleSelectOptionModal} from '../../fields/single-select/single-select-option-modal'
import {normalizeToFilterName} from '../../filter-bar/helpers/search-filter'
import {useSearch} from '../../filter-bar/search-context'
import {useBoardContext} from '../board-context'
import {type BoardDndEventData, isBoardDndCardData, isBoardDndColumnData} from '../board-dnd-context'
import {CellCardsPagination, ColumnCardsPagination, PlaceholderCard} from '../board-pagination'
import {DraggableCard} from '../card/draggable-card'
import {KeyboardMovingCardPlaceholder} from '../card/keyboard-moving-card-placeholder'
import {CARD_SIZE_ESTIMATE, COLUMN_PADDING, COLUMN_STYLE} from '../constants'
import {EmptyColumnSash} from '../empty-column-sash'
import {useCardSelection} from '../hooks/use-card-selection'
import {useColumnLimit} from '../hooks/use-column-limit'
import {ObserverProvider} from '../hooks/use-is-visible'
import {useMoveBoardColumn} from '../hooks/use-move-board-column'
import {useOmnibarVisibility} from '../hooks/use-omnibar-visibility'
import {
  isAddItemFocus,
  isFooterFocus,
  isLoadMoreItemsFocus,
  useBoardNavigation,
  useStableBoardNavigation,
} from '../navigation'
import styles from './column.module.css'
import {COLUMN_WIDTH, ColumnFrame} from './column-frame'
import {ColumnLimitModal} from './column-limit-modal'
import {EditableColumnName} from './editable-column-name'
import type {ColumnHeaderType} from './types'

type ColumnProps = {
  /** The vertical group represented by this column */
  verticalGroup: VerticalGroup

  /** Server generated ID for making paginated requests */
  groupId?: GroupId

  /** The list of items belonging to this column */
  items: ReadonlyArray<MemexItemModel>

  /** Whether this column's initial items are currently loading (used with MWL) */
  isLoading?: boolean

  /** The index of this column in the board */
  index: number

  /** Whether this column is editable by the user */
  isUserEditable: boolean

  /** Whether this column is editable by the user */
  isDraggable: boolean

  /**
   * Whether to scroll this column to an item on render
   *
   * This is useful to control scrolling to cards as new items are added to the
   * board.
   */
  scrollToItemId?: number

  /**
   * Whether to focus on the column name on initial render
   *
   * This is used to focus the names of columns after users add them.
   */
  initialNameFocus?: boolean

  /** A callback indicating the user wants to delete this column */
  onDelete?: (id: string) => Promise<void>

  /** A callback indicating the user wants to rename this column */
  onUpdateDetails: (updated: VerticalGroupColumnData, rollback: VerticalGroupColumnData) => Promise<void>

  /**
   * Does the vertical group correspond to an iteration which is the `current` iteration?
   */
  isCurrentIteration: boolean

  /**
   * Iteration date ranges for group by iteration titles
   */
  iterationDateRange: string

  /** Whether the column is hidden or not */
  hidden?: boolean

  /** Whether the column is part of the last horizontal grouping */
  isLastGroup?: boolean

  /**
   * The horizontal group applied, if there is one
   */
  horizontalGroup?: HorizontalGroup
  /** The type of header to render:
   * 'only': only the header, no items are rendered
   * 'hidden': no header is rendered
   * 'visible': the header and items are rendered
   */
  headerType?: ColumnHeaderType

  horizontalGroupIndex: number
  totalCount?: number
}

const COLUMN_HAS_OUTLINE_ATTRIBUTE = 'data-board-column-has-outline'

/**
 * Render a draggable board column.
 */
export const Column = memo(function Column({
  verticalGroup,
  groupId,
  items,
  isLoading = false,
  index,
  scrollToItemId,
  initialNameFocus,
  onDelete,
  onUpdateDetails,
  isDraggable,
  isUserEditable,
  isCurrentIteration,
  iterationDateRange,
  hidden,
  horizontalGroup,
  horizontalGroupIndex,
  headerType = 'visible',
  isLastGroup,
  // default this to 0 instead of items.length as it will be easier to see the issue in bug reports if it is 0
  // and not just the number of loaded items
  totalCount = 0,
}: React.PropsWithChildren<ColumnProps>) {
  const queryClient = useQueryClient()
  const {groupMetadata} = verticalGroup
  const {currentView} = useViews()
  const currentViewNumber = currentView?.number
  const dragRef = useRef<HTMLDivElement | null>(null)
  const dropRef = useRef<HTMLDivElement | null>(null)
  const dndContext = useDndContext()
  const isDragging = dndContext.active !== null
  const [isEditingName, setIsEditingName] = useState(false)
  const [isEditingDetails, setIsEditingDetails] = useState(false)
  const [isEditingColumnLimit, setIsEditingColumnLimit] = useState(false)
  const {enableOmnibar} = useOmnibarVisibility()
  const {state: focusState} = useBoardNavigation()
  const {hasWritePermissions} = ViewerPrivileges()
  const {resetSelection, filteredSelectedCards} = useCardSelection()
  const {insertFilter} = useSearch()
  const {groupByField, groupByFieldOptions} = useBoardContext()
  const {groupedByColumn} = useVerticalGroupedBy()
  const {postStats} = usePostStats()
  const {isSorted} = useSortedBy()
  const {columnLimit, updateColumnLimit} = useColumnLimit(verticalGroup)
  const overData: unknown = dndContext.over?.data.current
  const activeDragData: unknown = dndContext.active?.data.current
  const horizontalGroupId = horizontalGroup && 'value' in horizontalGroup ? horizontalGroup.value : undefined
  const isDraggingOverColumn =
    isBoardDndColumnData(overData) &&
    overData.verticalGroup.id === verticalGroup.id &&
    horizontalGroupIndex === overData.horizontalGroupIndex
  const isDraggingOverCardInColumn =
    isBoardDndCardData(overData) &&
    overData.verticalGroup.id === verticalGroup.id &&
    horizontalGroupIndex === overData.horizontalGroupIndex
  const buttonRef = useRef<HTMLButtonElement | null>(null)
  const {navigationDispatch} = useStableBoardNavigation()
  const {memex_table_without_limits} = useEnabledFeatures()

  const isDraggingOver = isDraggingOverColumn || isDraggingOverCardInColumn

  const showEmptyColumnSash = isDraggingOver && items.length === 0 && !isSorted && filteredSelectedCards.length <= 1

  const metadata = useMemo(() => ({id: verticalGroup.groupMetadata?.id}), [verticalGroup.groupMetadata?.id])

  const isAddItemDisabled = horizontalGroup?.sourceObject && shouldDisableGroupFooter(horizontalGroup.sourceObject)

  const drag = useDragWithIds({
    dragAxis: 'horizontal',
    dragID: verticalGroup.id,
    dragType: 'column',
    dragIndex: index,
    dragRef,
    disable: !isUserEditable || !isDraggable,
    metadata,
  })

  const {setNodeRef} = useDroppable({
    id: horizontalGroupId ? `${horizontalGroupId}-${verticalGroup.id}` : verticalGroup.id,
    data: {
      verticalGroup,
      type: 'column',
      ref: dragRef,
      index,
      horizontalGroupIndex,
    } satisfies BoardDndEventData,
  })
  setNodeRef(dragRef.current)

  useAutoScroll({
    active: isBoardDndCardData(activeDragData) && isDraggingOverCardInColumn,
    scrollRef: dropRef,
    strength: 50,
    deadZoneRatioY: 0.5,
  })

  const focusedCard = focusState.focus?.type === 'coordinate' ? focusState.focus : null

  const isMovingOverViaKeyboard = focusedCard?.details.x === index && !!focusedCard?.details.meta.keyboardMovingCard
  const isMovingCardsToColumn = isDraggingOver || isMovingOverViaKeyboard
  // Sash position is irrelevant when a column is sorted, so show the column outline instead
  const isMovingCardsToSortedColumn = isSorted && isMovingCardsToColumn
  // Cannot drag multiple cards to a particular position, so show column outline instead
  const isMovingMultipleCardsToColumn =
    isMovingCardsToColumn &&
    (filteredSelectedCards.length > 1 || (focusedCard?.details.meta.keyboardMovingCard?.cardIds.length ?? 0) > 1)
  const showColumnOutline = isMovingCardsToSortedColumn || isMovingMultipleCardsToColumn

  const hideColumnOnClick = useCallback(() => {
    if (groupedByColumn?.name) {
      const {dataType: groupDataType, databaseId, name} = groupedByColumn

      // correctly handle multi-word column names
      insertFilter(`-${normalizeToFilterName(groupedByColumn.name)}`, verticalGroup.name)
      postStats({
        name: BoardColumnMenuHide,
        context: JSON.stringify({dataType: groupDataType, databaseId, name}),
      })
    }
  }, [groupedByColumn, verticalGroup.name, insertFilter, postStats])

  const {moveColumn} = useMoveBoardColumn(groupByField)
  const isSingleSelect = groupByField?.dataType === MemexColumnDataType.SingleSelect

  const moveToLeftOnClick = useCallback(() => {
    if (!groupMetadata?.id || !isSingleSelect) {
      return
    }

    const currentIndex = findGroupOptionIndex(groupByFieldOptions, groupMetadata.id)
    const dropID = getGroupMetadataId(groupByFieldOptions[currentIndex - 1])

    if (!dropID) {
      return
    }

    moveColumn(groupMetadata?.id, dropID, 'before')
    // We close the menu after moving the column, otherwise its position isn't updated
    setGroupMenuOpen(false)
  }, [groupMetadata?.id, isSingleSelect, groupByFieldOptions, moveColumn])

  const moveToRightOnClick = useCallback(() => {
    if (!groupMetadata?.id || !isSingleSelect) {
      return
    }

    const currentIndex = findGroupOptionIndex(groupByFieldOptions, groupMetadata.id)
    const dropID = getGroupMetadataId(groupByFieldOptions[currentIndex + 1])

    if (!dropID) {
      return
    }

    moveColumn(groupMetadata?.id, dropID, 'after')
    // We close the menu after moving the column, otherwise its position isn't updated
    setGroupMenuOpen(false)
  }, [groupMetadata?.id, isSingleSelect, groupByFieldOptions, moveColumn])

  const renameOnClick = useCallback(() => {
    setIsEditingName(true)
  }, [])

  const submitRenameColumn = useCallback(
    (newName: string) => {
      if (!verticalGroup.groupMetadata?.id) return
      const update = {id: verticalGroup.groupMetadata?.id, name: newName}
      const rollback = {id: verticalGroup.groupMetadata?.id, name: verticalGroup.nameHtml}
      onUpdateDetails(update, rollback)
    },
    [onUpdateDetails, verticalGroup.nameHtml, verticalGroup.groupMetadata?.id],
  )

  const submitEditColumnLimit = async (limit: number | undefined) => {
    await updateColumnLimit(limit)
    setIsEditingColumnLimit(false)
  }

  const submitEditColumnDetails = (details: VerticalGroupColumnData) => {
    if (groupMetadata) {
      onUpdateDetails(details, groupMetadata)
    }
    setIsEditingDetails(false)
  }

  const addItem = useCallback(() => {
    enableOmnibar({columnId: verticalGroup.id, horizontalGroupIndex})
  }, [enableOmnibar, verticalGroup.id, horizontalGroupIndex])

  const onAddItemClick: React.MouseEventHandler = useCallback(
    e => {
      e.stopPropagation()
      addItem()
    },
    [addItem],
  )

  const onClick: React.MouseEventHandler = useCallback(() => {
    resetSelection()
  }, [resetSelection])

  const isAddItemButtonFocus =
    isAddItemFocus(focusState.focus) &&
    !isAddItemDisabled &&
    focusState.focus.details.verticalGroupId === verticalGroup.id &&
    horizontalGroupIndex === focusState.focus.details.horizontalGroupIndex

  const isAddingNewItems = isFooterFocus(focusState.focus)
    ? focusState.focus.details.verticalGroupId === verticalGroup.id &&
      horizontalGroupIndex === focusState.focus.details.horizontalGroupIndex
    : false

  const columnShouldScroll = isFooterFocus(focusState.focus)
    ? focusState.focus.details.verticalGroupId === verticalGroup.id && !horizontalGroupId && !memex_table_without_limits
    : false

  useLayoutEffect(() => {
    resetScrollPositionImmediately(dropRef.current)
  }, [currentViewNumber])

  useEffect(() => {
    if (!isAddItemButtonFocus || !buttonRef.current) {
      return
    }
    buttonRef.current.focus()
    buttonRef.current.scrollIntoView({block: 'nearest', inline: 'nearest', behavior: 'smooth'})
  }, [isAddItemButtonFocus])

  const onAddItemKeyDown: React.KeyboardEventHandler = useCallback(
    e => {
      const result = handleKeyboardNavigation(navigationDispatch, e)
      if (result.action) {
        suppressEvents(e)
      }
    },
    [navigationDispatch],
  )

  const {loadingState} = useViewLoadingState()

  const {hideItemsCount, getAggregatesForItems, getAggregatesForGroupId} = useAggregationSettings()

  // It's possible that at the first render pass, we won't be able to
  // determine the serverGroupId for the "no value" group, so we need
  // to check if it's available outside of the `useMemo` for getting
  // the aggregates, so that it can properly be included as a dependency.
  const serverGroupId = memex_table_without_limits
    ? getServerGroupIdForVerticalGroupId(queryClient, verticalGroup.id)
    : undefined

  const aggregates = memex_table_without_limits
    ? // eslint-disable-next-line react-hooks/react-compiler
      // eslint-disable-next-line react-hooks/rules-of-hooks
      useMemo(() => {
        if (serverGroupId != null) {
          return getAggregatesForGroupId(serverGroupId)
        }
        return []
      }, [getAggregatesForGroupId, serverGroupId])
    : // eslint-disable-next-line react-hooks/react-compiler
      // eslint-disable-next-line react-hooks/rules-of-hooks
      useMemo(() => getAggregatesForItems(items), [items, getAggregatesForItems])

  const editability = isAnySingleSelectColumnModel(groupedByColumn) ? 'singleSelectDetails' : 'name'

  const className = clsx(headerType, {
    'last-group': isLastGroup,
    'drag-outline': showColumnOutline,
  })

  const isLoadMoreItemsButtonFocused =
    isLoadMoreItemsFocus(focusState.focus) &&
    focusState.focus.details.verticalGroupId === verticalGroup.id &&
    horizontalGroupIndex === focusState.focus.details.horizontalGroupIndex

  const loadMoreItemsButtonOnKeyDown: React.KeyboardEventHandler = useCallback(
    e => {
      const result = handleKeyboardNavigation(navigationDispatch, e)
      if (result.action) {
        suppressEvents(e)
      }
    },
    [navigationDispatch],
  )

  const [groupMenuOpen, setGroupMenuOpen] = useState(false)
  const showPaginationComponent = memex_table_without_limits && headerType !== 'only' && groupId
  const isSwimlaneCell = hasServerGroupId(horizontalGroup) && horizontalGroup.serverGroupId

  return (
    <>
      <ColumnFrame
        id={verticalGroup.id}
        testingName={verticalGroup.name}
        sx={COLUMN_STYLE}
        ref={dragRef}
        {...drag.props}
        onClick={onClick}
        hidden={hidden}
        {...{[COLUMN_HAS_OUTLINE_ATTRIBUTE]: showColumnOutline}}
        className={className}
        headerContent={
          headerType === 'hidden' ? null : (
            <Box
              sx={{
                maxWidth: `${COLUMN_WIDTH}px`,
              }}
              className={styles.Box}
              {...drag.handle.props}
            >
              <div className={styles.Box_1}>
                <EditableColumnName
                  hideItemsCount={hideItemsCount}
                  columnLimit={columnLimit}
                  itemsCount={totalCount}
                  verticalGroup={verticalGroup}
                  onNameChange={submitRenameColumn}
                  isUserEditable={isUserEditable && editability === 'name'}
                  initialFocus={initialNameFocus}
                  isEditing={isEditingName}
                  loadingState={loadingState}
                  setIsEditing={setIsEditingName}
                />

                {loadingState === LoadingStates.loaded && (
                  <AggregateLabels
                    aggregates={aggregates}
                    hideItemsCount
                    itemsCount={totalCount}
                    counterClassName={styles.AggregateLabels}
                  />
                )}

                {isCurrentIteration && <CurrentIterationLabel className={styles.CurrentIterationLabel} />}
              </div>

              <div className={styles.Box_2}>
                {loadingState === LoadingStates.loading ? (
                  <Spinner
                    size="small"
                    aria-label="Loading data required to properly display view"
                    {...testIdProps('view-loading-indicator')}
                  />
                ) : loadingState === LoadingStates.missing ? null : (
                  isUserEditable && (
                    <GroupMenu
                      items={items}
                      open={groupMenuOpen}
                      setOpen={setGroupMenuOpen}
                      name={verticalGroup.name}
                      isColumn
                      onRename={editability === 'name' ? renameOnClick : undefined}
                      onEditDetails={
                        editability === 'singleSelectDetails' ? () => setIsEditingDetails(true) : undefined
                      }
                      onEditLimit={() => setIsEditingColumnLimit(true)}
                      onHide={hideColumnOnClick}
                      onDelete={!!groupMetadata && onDelete ? () => onDelete(groupMetadata.id) : undefined}
                      onMoveToLeft={moveToLeftOnClick}
                      onMoveToRight={moveToRightOnClick}
                      moveToLeftDisabled={index === 1}
                      moveToRightDisabled={isSingleSelect && index === groupByFieldOptions.length - 1}
                      isSingleSelect={isSingleSelect}
                    />
                  )
                )}
              </div>
            </Box>
          )
        }
      >
        {headerType !== 'hidden' && iterationDateRange && (
          <div
            style={{
              maxWidth: `${COLUMN_WIDTH}px`,
            }}
            className={styles.Box_3}
            {...testIdProps(`${verticalGroup.id}-date-range-board-header`)}
          >
            {iterationDateRange}
          </div>
        )}

        {headerType !== 'hidden' && (
          <SanitizedHtml
            style={{
              maxWidth: `${COLUMN_WIDTH}px`,
            }}
            className={styles.SanitizedHtml}
          >
            {isSingleSelectOption(groupMetadata) ? groupMetadata.descriptionHtml : ''}
          </SanitizedHtml>
        )}

        <div
          ref={dropRef}
          className={clsx('column-drop-zone', styles.Box_4)}
          {...testIdProps(`drop-zone-${verticalGroup.name}`)}
          {...{[DROP_TYPE_ATTRIBUTE]: 'card'}}
          style={{
            paddingTop: `${COLUMN_PADDING}px`,
            paddingBottom: `${COLUMN_PADDING}px`,
          }}
        >
          {showEmptyColumnSash && <EmptyColumnSash />}
          {/* We use a `null` (for window) rootRef instead of the drop ref so
        that we still render while dragging */}
          <ObserverProvider rootRef={null} sizeEstimate={CARD_SIZE_ESTIMATE} disableHide={isDragging}>
            {headerType !== 'only' &&
              items.length > 0 &&
              items.map((item, cardIndex) => {
                const focusType =
                  focusedCard?.details.x === index && focusedCard?.details.y === item.id
                    ? focusedCard.focusType
                    : undefined
                // disable dragging if Memex is readonly or for RedactedItems
                const isDragDisabled = !hasWritePermissions || item.contentType === ItemType.RedactedItem

                return (
                  <DraggableCard
                    key={item.id}
                    item={item}
                    scrollIntoView={item.id === scrollToItemId}
                    index={cardIndex}
                    verticalGroup={verticalGroup}
                    columnIndex={index}
                    focusType={focusType}
                    keyboardMovingCard={focusedCard?.details.meta.keyboardMovingCard}
                    isDragDisabled={isDragDisabled}
                    horizontalGroupId={horizontalGroupId}
                    horizontalGroupIndex={horizontalGroupIndex}
                  />
                )
              })}
            {/* The placeholder sash is only rendered when:
              1) There are no items in the column (when there are items, sash will be rendered by the card)
              2) Items are actually being rendered in the column (i.e., not just a column header)
              3) The focus state is currently in this vertical group (column) and horizontal group ("swimlane")
              4) The focused card is actively being moved via the keyboard
             */}
            {items.length === 0 /* [1] */ &&
              headerType !== 'only' /* [2] */ &&
              focusedCard?.details.x === index /* [3] */ &&
              focusedCard?.details.meta.horizontalGroupIndex === horizontalGroupIndex /* [3] */ &&
              focusedCard?.details.meta.keyboardMovingCard /* [4] */ && (
                <KeyboardMovingCardPlaceholder
                  horizontalGroupIndex={horizontalGroupIndex}
                  verticalGroup={verticalGroup}
                  columnIndex={index}
                  focusType={focusedCard.focusType}
                  keyboardMovingCard={focusedCard.details.meta.keyboardMovingCard}
                />
              )}
          </ObserverProvider>

          {headerType !== 'only' && (
            <IsAddingItemsIndicator isVisible={isAddingNewItems} shouldScroll={columnShouldScroll} />
          )}
          {showPaginationComponent && isSwimlaneCell && horizontalGroup.serverGroupId && (
            <CellCardsPagination
              groupId={groupId}
              secondaryGroupId={horizontalGroup.serverGroupId}
              loadMoreItemsButtonOnKeyDown={loadMoreItemsButtonOnKeyDown}
              isLoadMoreItemsButtonFocused={isLoadMoreItemsButtonFocused}
            />
          )}
          {isLoading && <PlaceholderCard />}
          {showPaginationComponent && !isSwimlaneCell && <ColumnCardsPagination groupId={groupId} />}
        </div>

        {headerType !== 'only' && hasWritePermissions && (
          <Button
            onClick={onAddItemClick}
            ref={buttonRef}
            variant="invisible"
            block
            size="large"
            alignContent="start"
            leadingVisual={PlusIcon}
            {...testIdProps('board-view-add-card-button')}
            disabled={isAddItemDisabled}
            onKeyDown={onAddItemKeyDown}
            title={
              (horizontalGroup?.sourceObject && getGroupFooterPlaceholder(horizontalGroup.sourceObject)) ||
              Resources.addItem
            }
            className={styles.Button}
          >
            {Resources.addItem}
          </Button>
        )}
      </ColumnFrame>
      {isEditingColumnLimit && (
        <ColumnLimitModal
          initialColumnLimit={columnLimit}
          onCancel={() => setIsEditingColumnLimit(false)}
          onSave={submitEditColumnLimit}
        />
      )}
      {isEditingDetails && isSingleSelectOption(groupMetadata) && (
        <SingleSelectOptionModal
          initialOption={groupMetadata}
          onCancel={() => setIsEditingDetails(false)}
          onSave={updatedOption => submitEditColumnDetails({...groupMetadata, ...updatedOption})}
        />
      )}
    </>
  )
})

const IsAddingItemsIndicator = ({isVisible, shouldScroll}: {isVisible: boolean; shouldScroll: boolean}) => {
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (shouldScroll) {
      ref.current?.scrollIntoView({behavior: 'smooth'})
    }
  }, [shouldScroll])

  return isVisible ? (
    <div ref={ref} className={styles.StyledPlaceholder} {...testIdProps('board-view-add-card-indicator')} />
  ) : null
}

/**
 * Finds the index of a group option in an array by its metadata ID
 */
function findGroupOptionIndex(options: Array<VerticalGroup>, groupMetadataId?: string): number {
  if (!groupMetadataId) return -1
  return options.findIndex(option => option.groupMetadata?.id === groupMetadataId)
}

/**
 * Gets the metadata ID from a vertical group if it exists
 */
function getGroupMetadataId(group?: VerticalGroup): string | undefined {
  return group?.groupMetadata?.id
}

import {DragOverlay} from '@github-ui/drag-and-drop'
import {noop} from '@github-ui/noop'
import {testIdProps} from '@github-ui/test-id-props'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {useTrackingRef} from '@github-ui/use-tracking-ref'
import {Box, useRefObjectAsForwardedRef} from '@primer/react'
import {useQueryClient} from '@tanstack/react-query'
import {forwardRef, memo, useCallback, useEffect, useImperativeHandle, useMemo, useRef, useState} from 'react'

import {MemexColumnDataType, SystemColumnId} from '../../api/columns/contracts/memex-column'
import type {NewOption} from '../../api/columns/contracts/single-select'
import type {UpdateColumnValueAction} from '../../api/columns/contracts/storage'
import type {CommandSpec, CommandTreeSpec} from '../../commands/command-tree'
import {useCommands} from '../../commands/hook'
import {getDraftItemUpdateColumnAction} from '../../features/grouping/helpers'
import {useHorizontalGroupedBy} from '../../features/grouping/hooks/use-horizontal-grouped-by'
import {useVerticalGroupedBy} from '../../features/grouping/hooks/use-vertical-grouped-by'
import {useVerticalGroups} from '../../features/grouping/hooks/use-vertical-groups'
import {useSliceBy} from '../../features/slicing/hooks/use-slice-by'
import {appendNewIteration} from '../../helpers/iteration-builder'
import {getLatestIteration} from '../../helpers/iterations'
import {shortcutFromEvent, SHORTCUTS} from '../../helpers/keyboard-shortcuts'
import {emptySingleSelectOption} from '../../helpers/new-column'
import {not_typesafe_nonNullAssertion} from '../../helpers/non-null-assertion'
import {isPortalActive} from '../../helpers/portal-elements'
import {shouldDisableGroupFooter} from '../../helpers/table-group-utilities'
import {ViewerPrivileges} from '../../helpers/viewer-privileges'
import {DragDropWithIdsContext, type OnDropWithIds, useDropWithIds} from '../../hooks/drag-and-drop/drag-and-drop'
import {useAggregationSettings} from '../../hooks/use-aggregation-settings'
import useAutoScroll from '../../hooks/use-auto-scroll'
import useBodyClass from '../../hooks/use-body-class'
import {useEnabledFeatures} from '../../hooks/use-enabled-features'
import {useMeasureScrollbars} from '../../hooks/use-measure-scrollbars'
import {useViews} from '../../hooks/use-views'
import {isVerticalGroupColumn} from '../../models/column-capabilities'
import type {GroupedHorizontalGroup} from '../../models/horizontal-group'
import type {MemexItemModel} from '../../models/memex-item-model'
import type {VerticalGroup} from '../../models/vertical-group'
import {MissingVerticalGroupId} from '../../models/vertical-group'
import {handleKeyboardNavigation, suppressEvents, suppressOmnibarEvents} from '../../navigation/keyboard'
import {useUpdateIterationConfiguration} from '../../state-providers/columns/use-update-iteration-configuration'
import {addNewGroup} from '../../state-providers/memex-items/query-client-api/memex-groups'
import {useAddFieldModal} from '../../state-providers/modals/use-add-field-modal'
import {useTemplateDialog} from '../../state-providers/template-dialog/use-template-dialog'
import {useViewOptionsMenuRef} from '../../state-providers/view-options/use-view-options-menu-ref'
import {SingleSelectOptionModal} from '../fields/single-select/single-select-option-modal'
import {Omnibar, type OmnibarRef} from '../omnibar/omnibar'
import {OmnibarContainer} from '../omnibar/omnibar-container'
import {OmnibarDrawer} from '../omnibar/omnibar-drawer'
import {DefaultOmnibarPlaceholder} from '../omnibar/omnibar-placeholder'
import type {OmnibarItemAttrs} from '../omnibar/types'
import {AddColumnModal} from '../react_table/add-column-modal'
import {SlicerItemsProvider, useSlicerItems} from '../slicer-panel/slicer-items-provider'
import {SlicerPanel} from '../slicer-panel/slicer-panel'
import {AddNewColumnOption} from './add-new-column-option'
import styles from './Board.module.css'
import {BoardContextProvider, useBoardContext} from './board-context'
import {BoardDndContext} from './board-dnd-context'
import {BoardFilterInput} from './board-filter-input'
import {HorizontalGroupsPagination} from './board-pagination'
import {DragOverlayCard} from './card/drag-overlay-card'
import {COLUMN_GAP, COLUMN_WIDTH} from './column/column-frame'
import {Columns} from './columns'
import {
  BASE_BOARD_CARD_AREA_STYLE,
  HORIZONTAL_GROUP_AREA_CONTAINER_STYLE,
  HORIZONTAL_GROUP_BOARD_CARD_AREA_STYLE,
  HORIZONTAL_GROUP_CONTAINER_STYLE,
  HORIZONTAL_GROUP_HEADER_STYLE,
} from './constants'
import {useAddBoardColumn} from './hooks/use-add-board-column'
import {BoardCardActionsProvider} from './hooks/use-board-card-actions'
import {useCardSelection} from './hooks/use-card-selection'
import {ObserverProvider} from './hooks/use-is-visible'
import {useMoveBoardColumn} from './hooks/use-move-board-column'
import {useOmnibarVisibility} from './hooks/use-omnibar-visibility'
import {HorizontalGroup} from './horizontal-group'
import {
  BoardNavigationProvider,
  type CardGrid,
  clearFocus,
  focusCard,
  focusPrevious,
  isFooterFocus,
  useBoardNavigation,
  useStableBoardNavigation,
} from './navigation'
import {CardSelectionProvider} from './selection'

interface BoardRef {
  focusIn: () => void
}

export const Board = memo(
  forwardRef<BoardRef>(function Board(_, ref) {
    return (
      <BoardContextProvider>
        <SlicerItemsProvider>
          <BoardLayout ref={ref} />
        </SlicerItemsProvider>
      </BoardContextProvider>
    )
  }),
)

const defaultGroupItems: Array<MemexItemModel> = []

const initialSelectedState = {selected: {}}
const BoardLayout = memo(
  forwardRef<BoardRef>(function BoardLayout(_, forwardedRef) {
    const {currentView} = useViews()
    const {memex_disable_autofocus} = useEnabledFeatures()

    // We need to find the first item in the left-most column to set initial focus for the board.
    // We iterate over the groups until we find one with at least one item, and pick that one
    // for the initial focus
    // If there are no items, we will default to focusing the omnibar.
    const {setGroupedBy} = useVerticalGroupedBy()
    const {groupedItems, groupByFieldOptions, compatibleColumns} = useBoardContext()

    const {sliceField} = useSliceBy()
    const {slicerItems} = useSlicerItems()

    const {showTemplateDialog} = useTemplateDialog()

    const ref = useRef<BoardRef>(null)
    useRefObjectAsForwardedRef(forwardedRef, ref)

    const currentViewNumber = currentView?.number
    const lastCurrentViewNumber = useRef<number | undefined>(undefined)
    useEffect(() => {
      if (memex_disable_autofocus || showTemplateDialog || lastCurrentViewNumber.current === currentViewNumber) return
      lastCurrentViewNumber.current = currentViewNumber

      // setTimeout ensures that the navigation context has time to init first
      // eslint-disable-next-line @eslint-react/web-api/no-leaked-timeout
      window.setTimeout(() => ref.current?.focusIn())
    }, [currentViewNumber, showTemplateDialog, memex_disable_autofocus])

    useCommands(() => {
      if (!currentView) {
        return null
      }

      const commands: Array<CommandSpec> = []
      const tree: CommandTreeSpec = ['c', 'Column field by...', commands]

      for (const [groupableIndex, column] of Object.entries(compatibleColumns)) {
        commands.push([
          groupableIndex,
          `Column field by: ${column.name}`,
          'column.field',
          () => setGroupedBy(currentView.number, column),
        ])
      }

      return tree
    }, [compatibleColumns, currentView, setGroupedBy])

    const navigationMetaRef = useTrackingRef<{cardGrid: CardGrid}>({
      cardGrid: groupedItems.horizontalGroups.map(hg => {
        return {
          horizontalGroupId: hg.value,
          isCollapsed: hg.isCollapsed,
          isFooterDisabled: !!hg.sourceObject && shouldDisableGroupFooter(hg.sourceObject),
          verticalGroups: groupByFieldOptions.map(verticalGroupFieldOption => {
            const verticalGroup = hg.itemsByVerticalGroup[verticalGroupFieldOption.id]
            const items = verticalGroup?.items ?? defaultGroupItems
            const hasMoreItems = verticalGroup && 'hasMoreItems' in verticalGroup ? !!verticalGroup.hasMoreItems : false
            return {
              verticalGroupId: verticalGroupFieldOption.id,
              items,
              hasMoreItems,
            }
          }),
        }
      }),
    })

    return (
      <DragDropWithIdsContext>
        <CardSelectionProvider initialState={initialSelectedState} metaRef={navigationMetaRef}>
          <BoardNavigationProvider metaRef={navigationMetaRef}>
            {sliceField && <SlicerPanel slicerItems={slicerItems} />}
            <BoardFilterInput />
            <BoardInner ref={ref} />
          </BoardNavigationProvider>
        </CardSelectionProvider>
      </DragDropWithIdsContext>
    )
  }),
)

const BoardInner = memo(
  forwardRef<BoardRef>(function BoardInner(_, ref) {
    const {groupedItems, groupByField, groupByFieldId, groupByFieldOptions, isLoading} = useBoardContext()
    const {groupedByColumn: horizontalGroupedByColumn} = useHorizontalGroupedBy()
    const {addColumn} = useAddBoardColumn(groupByField)
    const {moveColumn} = useMoveBoardColumn(groupByField)
    const {updateIterationConfiguration} = useUpdateIterationConfiguration()
    const scrollRef = useRef<HTMLDivElement | null>(null)
    const [isCreatingColumn, setIsCreatingColumn] = useState(false)
    const addNewColumnRef = useRef<HTMLButtonElement>(null)
    const didCancelCreatingColumnRef = useRef(false)
    const lastNewColumnNameRef = useRef<string | null>(null)
    const {navigationDispatch, stateRef} = useStableBoardNavigation()
    const {resetSelection, filteredSelectedCards} = useCardSelection()
    const {missingRequiredColumnData} = useViews()

    const onDrop: OnDropWithIds<{id: string}> = useCallback(
      ({dragMetadata, dropMetadata, side}) => {
        if (!dragMetadata || !dropMetadata) return
        const dragID = dragMetadata.id
        let dropID = dropMetadata.id
        // TODO: Currently, status fields are hard-coded, and our special `null`
        // value column always comes first. When that column is the drop target,
        // we change the target to be before the first *real* user-defined column.
        //
        // Instead, `groupedByState` should be turned into a `Map` that reflects
        // the real user-defined order of a single-select field (with our
        // client-only `null` column always as the first key).
        if (dropID === MissingVerticalGroupId) {
          const fieldKeys = Object.keys(groupedItems.allItemsByVerticalGroup)
          dropID = not_typesafe_nonNullAssertion(fieldKeys[1])
          side = 'before'
        }

        moveColumn(dragID, dropID, side || 'before')
      },
      [groupedItems.allItemsByVerticalGroup, moveColumn],
    )

    // the current item being dragged, however multiple items can be selected (see draggingItems below)
    const [draggingItem, setDraggingItem] = useState<MemexItemModel | null>(null)
    const isDragging = !!draggingItem

    const draggingItems = useMemo(
      // if multi-card selection is enabled we drag all the selected cards
      () =>
        filteredSelectedCards.length > 1 ? filteredSelectedCards : draggingItem ? [draggingItem] : defaultGroupItems,
      [draggingItem, filteredSelectedCards],
    )

    const drop = useDropWithIds<{id: string}>({
      dropID: 'board',
      dropType: 'column',
      dropRef: scrollRef,
      onDrop,
    })

    useAutoScroll({
      active: isDragging,
      scrollRef,
      strength: 50,
      deadZoneRatioX: 0.5,
      maxBufferX: COLUMN_WIDTH,
    })

    const onCreateColumnSave = useCallback(
      (option: NewOption) => {
        lastNewColumnNameRef.current = option.name
        addColumn(option)
        setIsCreatingColumn(false)
      },
      [addColumn],
    )

    const onCreateColumnCancel = useCallback(() => {
      didCancelCreatingColumnRef.current = true
      setIsCreatingColumn(false)
    }, [])

    useLayoutEffect(() => {
      if (didCancelCreatingColumnRef.current) {
        didCancelCreatingColumnRef.current = false
        addNewColumnRef.current?.focus()
      }
    })
    const omnibarRef = useRef<OmnibarRef>(null)
    const {enableOmnibar, disableOmnibar} = useOmnibarVisibility()
    const {horizontalScrollbarSize} = useMeasureScrollbars(scrollRef)
    const {memex_table_without_limits, memex_small_viewport_a11y} = useEnabledFeatures()
    const queryClient = useQueryClient()

    // We update `getPreviousItemId` when the column being added to changes.
    //
    // Additionally, because we don't know the ID of a new item until it's
    // persisted to the server, we also update the attributes whenever the items
    // the board is being rendered with changes. This is a best-effort to
    // hopefully ensure that a user's next card is inserted after the one before.
    //
    // Bugs (but not errors) will happen if they insert a new card before the
    // prior new card's persistence round-trip finishes—the card will be inserted
    // after the last card that had a completed round-trip in that column.
    const getPreviousItemId = (verticalGroupId: string, horizontalGroupIndex: number) => {
      const itemsForGroup = groupedItems.horizontalGroups[horizontalGroupIndex]?.itemsByVerticalGroup[verticalGroupId]
      if (memex_table_without_limits) {
        // we don't want to use a `previousItemId` for a MWL project. If the group has more data on the server
        // then the id here will be incorrect.
        // We could check to see if the group has more data on the server, but then the behavior of adding
        // an item would be different depending on if the column has more data.
        // Additionally, the table view doesn't ever send a previous item id when an item is added to the end of a
        // group, so by making this change, we're keeping the table and board behaviors consistent.
        return undefined
      }
      return itemsForGroup?.items.at(-1)?.id
    }

    const onKeyDown = useCallback(
      (e: KeyboardEvent) => {
        switch (shortcutFromEvent(e)) {
          case SHORTCUTS.CTRL_SPACE:
            if (omnibarRef.current?.isInputElement(e.target)) {
              disableOmnibar()
            } else {
              enableOmnibar()
            }
            break
          case SHORTCUTS.ESCAPE:
            if (omnibarRef.current?.isInputElement(e.target)) {
              disableOmnibar()
            }
            break
        }
      },
      [disableOmnibar, enableOmnibar],
    )

    const onBoardMouseDown: React.MouseEventHandler = useCallback(() => {
      if (stateRef.current && isFooterFocus(stateRef.current.focus)) {
        disableOmnibar()
      }
    }, [disableOmnibar, stateRef])

    const onBlur: React.FocusEventHandler = useCallback(
      e => {
        if (e.defaultPrevented) return
        const relatedTarget = e.relatedTarget as Node | null

        const newFocusIsInsideBoard = e.currentTarget.contains(relatedTarget)

        if (!newFocusIsInsideBoard && !omnibarRef.current?.isInputElement(relatedTarget)) {
          navigationDispatch(clearFocus())
          if (!isPortalActive()) resetSelection()
        }
      },
      [resetSelection, navigationDispatch],
    )

    useEffect(() => {
      window.addEventListener('keydown', onKeyDown)

      return () => {
        window.removeEventListener('keydown', onKeyDown)
      }
    }, [onKeyDown])

    const getFocusFirstCardAction = useCallback(() => {
      for (const [horizontalGroupIndex, horizontalGroup] of groupedItems.horizontalGroups.entries()) {
        for (const [verticalGroupIndex, verticalGroup] of groupByFieldOptions.entries()) {
          // find first vertical group with items
          const hasItems = verticalGroup && !!groupedItems.allItemsByVerticalGroup[verticalGroup.id]?.items.length

          if (!hasItems) continue

          // find first items in horizontal groups within the vertical group
          const nextFocusId = horizontalGroup.itemsByVerticalGroup[verticalGroup.id]?.items[0]?.id
          if (nextFocusId) {
            return focusCard(horizontalGroupIndex, verticalGroupIndex, nextFocusId)
          }
        }
      }
      return null
    }, [groupByFieldOptions, groupedItems.allItemsByVerticalGroup, groupedItems.horizontalGroups])

    useImperativeHandle(ref, () => ({
      focusIn: () => {
        const focusFirstCard = getFocusFirstCardAction()

        if (focusFirstCard) navigationDispatch(focusFirstCard)
        else enableOmnibar({columnId: MissingVerticalGroupId, horizontalGroupIndex: 0})
      },
    }))

    const {scrollToItemId, onNewItem} = useColumnShouldScroll()
    const {hasWritePermissions} = ViewerPrivileges()

    const addFieldClick = useCallback(async () => {
      if (!groupByField) {
        return
      }

      const fieldType = groupByField.dataType
      if (fieldType === MemexColumnDataType.Iteration) {
        // append a new iteration to the board without needing the user to set the name
        const {configuration} = groupByField.settings
        if (!configuration) {
          return
        }

        const fieldName = groupByField.name
        const updatedConfiguration = appendNewIteration(configuration, fieldName)
        const persistedConfiguration = await updateIterationConfiguration(groupByField, updatedConfiguration)

        if (memex_table_without_limits) {
          // Optimistically display the new iteration as a Board column
          if (!persistedConfiguration) return
          const newIteration = getLatestIteration(persistedConfiguration)
          if (!newIteration) return
          addNewGroup(queryClient, newIteration, newIteration.title)
        }

        return
      }

      setIsCreatingColumn(true)
    }, [groupByField, memex_table_without_limits, queryClient, updateIterationConfiguration])

    useBodyClass('is-dragging', !!draggingItem)

    const {hideItemsCount, getAggregatesForItems, getAggregatesForGroupId} = useAggregationSettings()
    const {setShowAddFieldModal, showAddFieldModal} = useAddFieldModal()
    const {anchorRef} = useViewOptionsMenuRef()
    const hideColumn = useCallback(
      (verticalGroup: VerticalGroup) => {
        const filteredItemsFromField =
          groupedItems.allItemsByVerticalGroup[verticalGroup.id]?.items ?? defaultGroupItems

        return (
          filteredItemsFromField.length === 0 &&
          verticalGroup.id === MissingVerticalGroupId &&
          !missingRequiredColumnData &&
          !isLoading
        )
      },
      [groupedItems.allItemsByVerticalGroup, isLoading, missingRequiredColumnData],
    )
    const totalColumnsWidth = useMemo(() => {
      const visibleColumns = groupByFieldOptions.filter(group => !hideColumn(group))
      return visibleColumns.length * (COLUMN_WIDTH + COLUMN_GAP)
    }, [groupByFieldOptions, hideColumn])

    const headerRef = useRef<HTMLDivElement>(null)

    return (
      <>
        <BoardCardActionsProvider
          groupByFieldId={groupByFieldId}
          horizontalGroupByFieldId={horizontalGroupedByColumn?.id}
        >
          <BoardDndContext setDraggingItem={setDraggingItem}>
            <div data-hpc className={styles.Box}>
              <ObserverProvider rootRef={scrollRef}>
                <Box
                  {...testIdProps('board-view')}
                  ref={scrollRef}
                  onPointerDown={onBoardMouseDown}
                  onBlur={onBlur}
                  {...drop.props}
                  sx={
                    groupedItems.isHorizontalGrouped
                      ? HORIZONTAL_GROUP_BOARD_CARD_AREA_STYLE
                      : BASE_BOARD_CARD_AREA_STYLE
                  }
                  data-memex-small-viewport-a11y={memex_small_viewport_a11y}
                  className={styles.boardView}
                >
                  {groupedItems.isHorizontalGrouped ? (
                    <>
                      <Box sx={HORIZONTAL_GROUP_HEADER_STYLE}>
                        <Box ref={headerRef} sx={HORIZONTAL_GROUP_CONTAINER_STYLE}>
                          <Columns
                            groupByFieldOptions={groupByFieldOptions}
                            itemsGroupedByField={groupedItems.allItemsByVerticalGroup}
                            groupByField={groupByField}
                            isLoading={isLoading}
                            scrollToItemId={scrollToItemId}
                            lastNewColumnNameRef={lastNewColumnNameRef}
                            headerType={groupedItems.horizontalGroups.length > 0 ? 'only' : undefined}
                            hideColumn={hideColumn}
                            horizontalGroupIndex={0}
                          />
                        </Box>
                        {hasWritePermissions && !isCreatingColumn && (
                          // We need to wrap the AddNewColumnOption in a div and position absolutely
                          // to avoid the height of the container changing when the AddNewColumnOption is opened
                          <div>
                            <AddNewColumnOption ref={addNewColumnRef} onClick={addFieldClick} />
                          </div>
                        )}
                      </Box>
                      <Box
                        sx={HORIZONTAL_GROUP_AREA_CONTAINER_STYLE}
                        style={{minWidth: `${totalColumnsWidth}px`}}
                        {...testIdProps('swimlanes-container')}
                      >
                        {groupedItems.horizontalGroups.map((horizontalGroup, index) => {
                          const aggregates = memex_table_without_limits
                            ? horizontalGroup.serverGroupId
                              ? getAggregatesForGroupId(horizontalGroup.serverGroupId)
                              : []
                            : getAggregatesForItems(horizontalGroup.rows)

                          return (
                            <HorizontalGroup
                              key={horizontalGroup.value}
                              horizontalGroup={horizontalGroup}
                              headerRef={headerRef}
                              aggregates={aggregates}
                              hideItemsCount={hideItemsCount}
                              groupByFieldOptions={groupByFieldOptions}
                              groupByField={groupByField}
                              scrollToItemId={scrollToItemId}
                              lastNewColumnNameRef={lastNewColumnNameRef}
                              hideColumn={hideColumn}
                              groupedItems={groupedItems}
                              index={index}
                              draggingItems={draggingItems}
                              scrollRef={scrollRef}
                            />
                          )
                        })}
                        {memex_table_without_limits && !isLoading && <HorizontalGroupsPagination />}
                      </Box>
                    </>
                  ) : (
                    <>
                      <Columns
                        groupByFieldOptions={groupByFieldOptions}
                        itemsGroupedByField={groupedItems.horizontalGroups[0].itemsByVerticalGroup}
                        groupByField={groupByField}
                        isLoading={isLoading}
                        scrollToItemId={scrollToItemId}
                        lastNewColumnNameRef={lastNewColumnNameRef}
                        hideColumn={hideColumn}
                        horizontalGroupIndex={0}
                      />
                      {hasWritePermissions && !isCreatingColumn && (
                        <AddNewColumnOption ref={addNewColumnRef} onClick={addFieldClick} />
                      )}
                    </>
                  )}
                  {isCreatingColumn ? (
                    <SingleSelectOptionModal
                      initialOption={emptySingleSelectOption}
                      onSave={onCreateColumnSave}
                      onCancel={onCreateColumnCancel}
                    />
                  ) : null}
                </Box>
              </ObserverProvider>
              {hasWritePermissions && (
                <BoardOmnibar
                  ref={omnibarRef}
                  horizontalScrollbarSize={horizontalScrollbarSize}
                  getPreviousItemId={getPreviousItemId}
                  onNewItem={onNewItem}
                />
              )}
              {showAddFieldModal && (
                <AddColumnModal
                  isOpen={showAddFieldModal}
                  setOpen={setShowAddFieldModal}
                  anchorRef={anchorRef}
                  onSave={noop}
                />
              )}
            </div>
            <DragOverlay dropAnimation={null}>
              {draggingItems.map(selectedItem => (
                <DragOverlayCard key={selectedItem.id} item={selectedItem} />
              ))}
            </DragOverlay>
          </BoardDndContext>
        </BoardCardActionsProvider>
      </>
    )
  }),
)

type BoardOmnibarProps = {
  horizontalScrollbarSize: number | null
  onNewItem: (model: MemexItemModel) => void
  getPreviousItemId: (columnBeingAddedTo: string, horizontalGroupIndex: number) => number | undefined
}

const BoardOmnibar = memo(
  forwardRef<OmnibarRef, BoardOmnibarProps>(function BoardOmnibar(
    {horizontalScrollbarSize, onNewItem, getPreviousItemId},
    forwardedRef,
  ) {
    const {groupedItems, groupByFieldOptions} = useBoardContext()
    const omnibarDrawerRef = useRef<HTMLDivElement>(null)
    const omnibarContainerRef = useRef<HTMLDivElement>(null)
    const {state, navigationDispatch} = useBoardNavigation()
    const {enableOmnibar, disableOmnibar} = useOmnibarVisibility()
    const isOmnibarEnabled = isFooterFocus(state.focus)
    const {groupedByColumn} = useVerticalGroupedBy()
    const {getServerGroupIdForVerticalGroupId} = useVerticalGroups()
    const {memex_table_without_limits} = useEnabledFeatures()

    const omnibarRef = useRef<OmnibarRef>(null)
    useRefObjectAsForwardedRef(forwardedRef, omnibarRef)

    useLayoutEffect(() => {
      if (isOmnibarEnabled) {
        // eslint-disable-next-line @eslint-react/web-api/no-leaked-timeout
        window.setTimeout(() => omnibarRef.current?.focus())
        // Prevent browser from attempt to scroll drawer while container is animating.
        if (omnibarDrawerRef.current) omnibarDrawerRef.current.scrollTop = 0
      } else {
        // eslint-disable-next-line github/no-blur
        omnibarRef.current?.blur()
      }
    }, [disableOmnibar, isOmnibarEnabled, enableOmnibar, omnibarRef])

    const omnibarItemAttrs: OmnibarItemAttrs | null = !memex_table_without_limits
      ? // eslint-disable-next-line react-hooks/react-compiler
        // eslint-disable-next-line react-hooks/rules-of-hooks
        useMemo(() => {
          if (!isFooterFocus(state.focus)) return null

          // Vertical group only supports single select & iteration options.
          if (!groupedByColumn || !isVerticalGroupColumn(groupedByColumn.dataType)) return null

          const updateColumnActions: Array<UpdateColumnValueAction> = []

          const verticalGroupId = state.focus.details.verticalGroupId
          const verticalGroup = groupByFieldOptions.find(group => group.id === verticalGroupId)

          if (verticalGroup?.groupMetadata) {
            // Appease the TypeScript gods.
            if (groupedByColumn.id === SystemColumnId.Status) {
              updateColumnActions.push({
                dataType: groupedByColumn.dataType,
                memexProjectColumnId: groupedByColumn.id,
                value: {id: verticalGroup.groupMetadata.id},
              })
            } else {
              updateColumnActions.push({
                dataType: groupedByColumn.dataType,
                memexProjectColumnId: groupedByColumn.id,
                value: {id: verticalGroup.groupMetadata.id},
              } as UpdateColumnValueAction)
            }
          }

          const horizontalGroup = groupedItems.horizontalGroups[state.focus.details.horizontalGroupIndex]
          if (horizontalGroup) {
            const sourceObject = 'sourceObject' in horizontalGroup ? horizontalGroup.sourceObject : undefined

            if (sourceObject) {
              const columnAction = getDraftItemUpdateColumnAction(sourceObject)
              if (columnAction) {
                updateColumnActions.push(columnAction)
              }
            }
          }

          const previousItemId = getPreviousItemId(verticalGroupId, state.focus.details.horizontalGroupIndex)

          return {
            updateColumnActions,
            previousItemId,
          }
        }, [state.focus, groupedByColumn, groupByFieldOptions, groupedItems.horizontalGroups, getPreviousItemId])
      : // eslint-disable-next-line react-hooks/react-compiler
        // eslint-disable-next-line react-hooks/rules-of-hooks
        useMemo(() => {
          if (!isFooterFocus(state.focus)) return null

          // Vertical group only supports single select & iteration options.
          if (!groupedByColumn || !isVerticalGroupColumn(groupedByColumn.dataType)) return null

          const updateColumnActions: Array<UpdateColumnValueAction> = []

          const verticalGroupId = state.focus.details.verticalGroupId
          const verticalGroup = groupByFieldOptions.find(group => group.id === verticalGroupId)

          if (verticalGroup?.groupMetadata) {
            // Appease the TypeScript gods.
            if (groupedByColumn.id === SystemColumnId.Status) {
              updateColumnActions.push({
                dataType: groupedByColumn.dataType,
                memexProjectColumnId: groupedByColumn.id,
                value: {id: verticalGroup.groupMetadata.id},
              })
            } else {
              updateColumnActions.push({
                dataType: groupedByColumn.dataType,
                memexProjectColumnId: groupedByColumn.id,
                value: {id: verticalGroup.groupMetadata.id},
              } as UpdateColumnValueAction)
            }
          }

          const horizontalGroup = groupedItems.horizontalGroups[state.focus.details.horizontalGroupIndex]
          const horizontalGroupId = (horizontalGroup as GroupedHorizontalGroup)?.serverGroupId
          if (horizontalGroup) {
            const sourceObject = 'sourceObject' in horizontalGroup ? horizontalGroup.sourceObject : undefined

            if (sourceObject) {
              const columnAction = getDraftItemUpdateColumnAction(sourceObject)
              if (columnAction) {
                updateColumnActions.push(columnAction)
              }
            }
          }

          const previousItemId = getPreviousItemId(verticalGroupId, state.focus.details.horizontalGroupIndex)

          const groupId = getServerGroupIdForVerticalGroupId
            ? getServerGroupIdForVerticalGroupId(verticalGroupId)
            : verticalGroupId
          return {
            updateColumnActions,
            previousItemId,
            groupId,
            secondaryGroupId: horizontalGroupId,
          }
        }, [
          state.focus,
          groupedByColumn,
          groupByFieldOptions,
          groupedItems.horizontalGroups,
          getPreviousItemId,
          getServerGroupIdForVerticalGroupId,
        ])

    const onKeyDown: React.KeyboardEventHandler = useCallback(
      e => {
        const result = handleKeyboardNavigation(navigationDispatch, e)
        if (result.action) {
          suppressOmnibarEvents(e, result.keyAsShortcut)
        } else if (result.keyAsShortcut === SHORTCUTS.ESCAPE) {
          navigationDispatch(focusPrevious())
          suppressEvents(e)
        }
      },
      [navigationDispatch],
    )

    const groupingMetadata = useMemo(() => {
      if (!isFooterFocus(state.focus)) return

      const verticalGroupId = state.focus.details.verticalGroupId
      const verticalGroup = groupByFieldOptions.find(group => group.id === verticalGroupId)
      const horizontalGroup = groupedItems.horizontalGroups[state.focus.details.horizontalGroupIndex]
      if (!horizontalGroup) return

      const sourceObject = 'sourceObject' in horizontalGroup ? horizontalGroup.sourceObject : undefined
      if (!sourceObject || !verticalGroup?.groupMetadata) return

      // TODO: Investigate whether sourceObject and value
      // should both be based on vertical or horizontal group.
      return {
        value: verticalGroup.groupMetadata.id,
        sourceObject,
      }
    }, [state.focus, groupByFieldOptions, groupedItems.horizontalGroups])

    return (
      <OmnibarDrawer ref={omnibarDrawerRef} horizontalScrollbarSize={horizontalScrollbarSize}>
        <OmnibarContainer
          ref={omnibarContainerRef}
          horizontalScrollbarSize={horizontalScrollbarSize}
          disableBlur
          isFixed
          data-omnibar-enabled={isOmnibarEnabled ? 'true' : 'false'}
          className={styles.OmnibarContainer}
        >
          <Omnibar
            ref={omnibarRef}
            newItemAttributes={omnibarItemAttrs ?? undefined}
            groupingMetadata={groupingMetadata}
            onAddItem={onNewItem}
            onKeyDown={onKeyDown}
            isFixed
            defaultPlaceholder={DefaultOmnibarPlaceholder}
          />
        </OmnibarContainer>
      </OmnibarDrawer>
    )
  }),
)

/**
 * When a new card is added to the board, set the column that should currently
 * scroll-to-bottom to be the column the new item was added to.
 */
const useColumnShouldScroll = () => {
  const scrollToItemIdRef = useRef<number | undefined>(undefined)

  useEffect(() => {
    scrollToItemIdRef.current = undefined
  })

  const onNewItem = useCallback((model: MemexItemModel) => {
    scrollToItemIdRef.current = model.id
  }, [])

  return {
    onNewItem,

    scrollToItemId: scrollToItemIdRef.current,
  }
}

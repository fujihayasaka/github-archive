import type {QueryClient} from '@tanstack/react-query'
import {useQueryClient} from '@tanstack/react-query'
import {createContext, useCallback, useContext, useMemo} from 'react'

import type {UpdateColumnValueAction} from '../../../api/columns/contracts/domain'
import {
  MemexColumnDataType,
  type MemexProjectColumnId,
  type SystemColumnId,
} from '../../../api/columns/contracts/memex-column'
import {isItemMovingWithinSortedValue} from '../../../features/sorting/is-item-moving-within-sorted-value'
import {DropSide} from '../../../helpers/dnd-kit/drop-helpers'
import {isSingleSelectOrIterationColumnValue} from '../../../helpers/parsing'
import {useGetUpdateForGroupDropEvent} from '../../../hooks/drag-and-drop/use-group-drop-handler'
import {useBulkUpdateItems} from '../../../hooks/use-bulk-update-items'
import {useEnabledFeatures} from '../../../hooks/use-enabled-features'
import {useSortedBy} from '../../../hooks/use-sorted-by'
import {buildUpdateItemActions, useUpdateAndReorderItem} from '../../../hooks/use-update-item'
import {hasServerGroupId, type HorizontalGroup} from '../../../models/horizontal-group'
import type {MemexItemModel} from '../../../models/memex-item-model'
import {MissingVerticalGroupId, type VerticalGroup} from '../../../models/vertical-group'
import {getServerGroupIdForVerticalGroupId} from '../../../state-providers/memex-items/query-client-api/memex-groups'
import {
  isMemexItemInGroup,
  type OptimisticUpdateRollbackData,
  rollbackMemexItemData,
  updateGroupForMemexItems,
} from '../../../state-providers/memex-items/query-client-api/memex-items'
import type {ReorderItemData} from '../../../state-providers/memex-items/types'
import {Resources} from '../../../strings'
import useToasts, {ToastType} from '../../toasts/use-toasts'
import {useBoardItems} from './use-board-items'

export const CardPositionType = {
  TOP: 'top',
  BOTTOM: 'bottom',
} as const
export type CardPositionType = ObjectValues<typeof CardPositionType>

type BoardCardActionsContextType = {
  /** Reorders a card within a column, and optionally moves it to a new column */
  moveCard: (
    cardToMove: MemexItemModel,
    previousCardId: number | undefined,
    side: 'top' | 'bottom',
    newVerticalGroup?: VerticalGroup,
    oldVerticalGroupId?: string,
    dragHorizontalGroup?: HorizontalGroup,
    dropHorizontalGroup?: HorizontalGroup,
  ) => Promise<void>
  /** Moves multiple cards to a new column */
  moveCards: (
    selectedItems: Array<MemexItemModel>,
    newVerticalGroup: VerticalGroup,
    dragHorizontalGroup?: HorizontalGroup,
    dropHorizontalGroup?: HorizontalGroup,
  ) => Promise<void>
  /** Moves a card to the top or bottom position within its current column */
  moveCardToPosition: (cardToMoveId: number, verticalGroupId: string, position: 'top' | 'bottom') => Promise<void>
}

const BoardCardActionsContext = createContext<BoardCardActionsContextType | null>(null)

export const BoardCardActionsProvider: React.FC<{
  groupByFieldId: number | typeof SystemColumnId.Status
  horizontalGroupByFieldId: MemexProjectColumnId | undefined
  children: React.ReactNode
}> = ({groupByFieldId, horizontalGroupByFieldId, children}) => {
  const {updateAndReorderItem} = useUpdateAndReorderItem()
  const {groupedItems} = useBoardItems()
  const {bulkUpdateMultipleColumnValues} = useBulkUpdateItems()
  const {getUpdateForGroupDropEvent, handleGroupDropRequestError} = useGetUpdateForGroupDropEvent()
  const {memex_table_without_limits} = useEnabledFeatures()
  const {sorts, clearSortedBy} = useSortedBy()
  const {addToast} = useToasts()
  const queryClient = useQueryClient()

  const moveCardMWLDisabled = useCallback(
    async (
      cardToMove: MemexItemModel,
      previousCardId: number | undefined,
      side: 'top' | 'bottom',
      newVerticalGroup?: VerticalGroup,
      _oldVerticalGroupId?: string,
      dragHorizontalGroup?: HorizontalGroup,
      dropHorizontalGroup?: HorizontalGroup,
    ) => {
      // skip if we're over the same card
      if (cardToMove.id === previousCardId) {
        return
      }

      const updateColumnActions: Array<UpdateColumnValueAction> = []
      let horizontalGroupActionFailed = false

      if (
        dragHorizontalGroup?.sourceObject &&
        dropHorizontalGroup?.sourceObject &&
        dragHorizontalGroup.value !== dropHorizontalGroup.value
      ) {
        const columnAction = await getUpdateForGroupDropEvent({
          activeItem: cardToMove,
          activeItemGroup: dragHorizontalGroup,
          overItemGroup: dropHorizontalGroup,
        })

        if (columnAction) {
          updateColumnActions.push(columnAction)
        } else {
          horizontalGroupActionFailed = true
        }
      }

      if (newVerticalGroup && !horizontalGroupActionFailed) {
        updateColumnActions.push({
          dataType: MemexColumnDataType.SingleSelect,
          memexProjectColumnId: groupByFieldId,
          value: {id: newVerticalGroup.groupMetadata?.id ?? ''},
        })
      }

      const dropSide = side === 'top' ? DropSide.BEFORE : DropSide.AFTER
      const reorderData = previousCardId != null ? {overItemId: previousCardId, side: dropSide} : undefined

      const updateItemData = buildUpdateItemActions(updateColumnActions, reorderData)

      if (!updateItemData) {
        return
      }

      try {
        await updateAndReorderItem(cardToMove.id, updateItemData, {layoutType: 'board'})
      } catch (error) {
        handleGroupDropRequestError(error)
      }
    },
    [getUpdateForGroupDropEvent, groupByFieldId, handleGroupDropRequestError, updateAndReorderItem],
  )

  const moveCardMWLEnabled = useCallback(
    async (
      cardToMove: MemexItemModel,
      previousCardId: number | undefined,
      side: 'top' | 'bottom',
      newVerticalGroup?: VerticalGroup,
      oldVerticalGroupId?: string,
      dragHorizontalGroup?: HorizontalGroup,
      dropHorizontalGroup?: HorizontalGroup,
    ) => {
      // skip if we're over the same card
      if (cardToMove.id === previousCardId) {
        return
      }

      const updateColumnActions: Array<UpdateColumnValueAction> = []
      let horizontalGroupActionFailed = false

      if (
        dragHorizontalGroup?.sourceObject &&
        dropHorizontalGroup?.sourceObject &&
        dragHorizontalGroup.value !== dropHorizontalGroup.value
      ) {
        const columnAction = await getUpdateForGroupDropEvent({
          activeItem: cardToMove,
          activeItemGroup: dragHorizontalGroup,
          overItemGroup: dropHorizontalGroup,
        })

        if (columnAction) {
          updateColumnActions.push(columnAction)
        } else {
          horizontalGroupActionFailed = true
        }
      }

      if (newVerticalGroup && newVerticalGroup.id !== oldVerticalGroupId && !horizontalGroupActionFailed) {
        updateColumnActions.push({
          dataType: MemexColumnDataType.SingleSelect,
          memexProjectColumnId: groupByFieldId,
          value: {id: newVerticalGroup.groupMetadata?.id ?? ''},
        })
      }

      const dropSide = side === 'top' ? DropSide.BEFORE : DropSide.AFTER
      // If there is no `previousCardId` it means we're dropping into an empty group
      // so we need to include the an `overGroupId` in the `reorderData`.
      const reorderData: ReorderItemData =
        previousCardId != null
          ? {overItemId: previousCardId, side: dropSide}
          : {overGroupId: groupedItems.allItemsByVerticalGroup[newVerticalGroup?.id || '']?.groupId || ''}

      if ('overGroupId' in reorderData && hasServerGroupId(dropHorizontalGroup)) {
        reorderData.overSecondaryGroupId = dropHorizontalGroup.serverGroupId
      }

      const updateItemData = buildUpdateItemActions(updateColumnActions, reorderData)

      if (!updateItemData) {
        return
      }

      const moveIsWithinSameColumn = oldVerticalGroupId != null && oldVerticalGroupId === newVerticalGroup?.id
      const moveIsWithinSameSwimlane = dragHorizontalGroup?.sourceObject === dropHorizontalGroup?.sourceObject
      const droppingInEmptyRow = 'overGroupId' in reorderData

      // We don't want to allow a user to attempt to drag and drop an item _outside of items
      // with the same sort value_ within the same column in a sorted board view.
      if (moveIsWithinSameColumn && moveIsWithinSameSwimlane && !droppingInEmptyRow) {
        // If we have a horizontal group, we want to use the items from the cell for that swimlane/column
        // combination - otherwise, just look up the items for the column.
        const itemsInGroup =
          dropHorizontalGroup != null
            ? dropHorizontalGroup.itemsByVerticalGroup[oldVerticalGroupId]
            : groupedItems.allItemsByVerticalGroup[oldVerticalGroupId]

        if (itemsInGroup) {
          for (const sort of sorts) {
            const showToast = !isItemMovingWithinSortedValue(
              cardToMove,
              sort.column,
              itemsInGroup.items,
              reorderData.overItemId,
              reorderData.side,
            )
            if (showToast) {
              const action = {
                text: Resources.cannotReorderForSortAction,
                handleClick: () => clearSortedBy(),
              }

              // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
              addToast({
                message: Resources.cannotReorderForSortMessage,
                type: ToastType.warning,
                action,
              })

              return
            }
          }
        }
      }

      try {
        await updateAndReorderItem(cardToMove.id, updateItemData, {layoutType: 'board'})
      } catch (error) {
        handleGroupDropRequestError(error)
      }
    },
    [
      addToast,
      clearSortedBy,
      getUpdateForGroupDropEvent,
      groupByFieldId,
      groupedItems.allItemsByVerticalGroup,
      handleGroupDropRequestError,
      sorts,
      updateAndReorderItem,
    ],
  )

  const moveCard = memex_table_without_limits ? moveCardMWLEnabled : moveCardMWLDisabled

  const moveCardToPosition = useCallback(
    async (cardToMoveId: number, verticalGroupId: string, position: CardPositionType) => {
      // Find the first/last item in the current column
      const columnItems = groupedItems.allItemsByVerticalGroup[verticalGroupId]?.items
      const item = position === CardPositionType.TOP ? columnItems?.at(0) : columnItems?.at(-1)
      if (!item) return

      const reorderData = {
        overItemId: item.id,
        side: position === CardPositionType.TOP ? DropSide.BEFORE : DropSide.AFTER,
      }
      const updateItemData = buildUpdateItemActions(undefined, reorderData)
      if (!updateItemData) {
        return
      }
      await updateAndReorderItem(cardToMoveId, updateItemData, {})
    },
    [groupedItems.allItemsByVerticalGroup, updateAndReorderItem],
  )

  const moveCards = useCallback(
    async (
      selectedItems: Array<MemexItemModel>,
      newVerticalGroup: VerticalGroup,
      dragHorizontalGroup?: HorizontalGroup,
      dropHorizontalGroup?: HorizontalGroup,
    ) => {
      const allItemsInTargetColumn = memex_table_without_limits
        ? isEveryItemInColumnPWL(queryClient, selectedItems, newVerticalGroup)
        : isEveryItemInColumn(selectedItems, newVerticalGroup, groupByFieldId)
      // skip if all the items are already in the target column and there is no secondary grouping
      if (!horizontalGroupByFieldId && allItemsInTargetColumn) {
        return
      }

      const itemUpdates = []
      let horizontalGroupActionFailed = false

      for (const item of selectedItems) {
        const updateColumnActions: Array<UpdateColumnValueAction> = []

        if (dragHorizontalGroup?.sourceObject && dropHorizontalGroup?.sourceObject) {
          const columnAction = await getUpdateForGroupDropEvent({
            activeItem: item,
            activeItemGroup: dragHorizontalGroup,
            overItemGroup: dropHorizontalGroup,
          })

          if (columnAction) {
            updateColumnActions.push(columnAction)
          } else {
            horizontalGroupActionFailed = true
            break
          }
        }

        if (newVerticalGroup && !horizontalGroupActionFailed) {
          updateColumnActions.push({
            dataType: MemexColumnDataType.SingleSelect,
            memexProjectColumnId: groupByFieldId,
            value: {id: newVerticalGroup.groupMetadata?.id ?? ''},
          })
        }

        itemUpdates.push({
          itemId: item.id,
          updates: updateColumnActions,
        })
      }

      if (!horizontalGroupActionFailed) {
        let rollbackData: OptimisticUpdateRollbackData | undefined = undefined
        try {
          if (memex_table_without_limits) {
            const newGroupId = getServerGroupIdForVerticalGroupId(queryClient, newVerticalGroup.id)
            if (newGroupId) {
              const newSecondaryGroupId = hasServerGroupId(dropHorizontalGroup)
                ? dropHorizontalGroup.serverGroupId
                : undefined
              rollbackData = updateGroupForMemexItems(queryClient, selectedItems, newGroupId, newSecondaryGroupId)
            }
          }
          await bulkUpdateMultipleColumnValues(itemUpdates)
        } catch (error) {
          handleGroupDropRequestError(error)
          if (rollbackData) {
            // This will only be defined if we called `updateGroupForMemexItems`, so memex_table_without_limits is true
            rollbackMemexItemData(queryClient, rollbackData)
          }
        }
      }
    },
    [
      bulkUpdateMultipleColumnValues,
      getUpdateForGroupDropEvent,
      groupByFieldId,
      handleGroupDropRequestError,
      horizontalGroupByFieldId,
      memex_table_without_limits,
      queryClient,
    ],
  )

  const boardCardActionsContextValue = useMemo(
    () => ({moveCard, moveCards, moveCardToPosition}),
    [moveCard, moveCardToPosition, moveCards],
  )

  return (
    <BoardCardActionsContext.Provider value={boardCardActionsContextValue}>{children}</BoardCardActionsContext.Provider>
  )
}

export function useBoardCardActions() {
  const value = useContext(BoardCardActionsContext)

  if (value == null) {
    throw new Error(`useBoardCardActions must be used within a BoardCardActionsContext`)
  }

  return value
}

// checks whether every item is already in the target column
export function isEveryItemInColumn(
  selectedItems: Array<MemexItemModel>,
  targetVerticalGroup: VerticalGroup,
  groupByFieldId: number | 'Status',
) {
  return selectedItems.every(item => {
    const columnValue = item.columns[groupByFieldId]

    if (columnValue) {
      return (
        isSingleSelectOrIterationColumnValue(columnValue) && columnValue.id === targetVerticalGroup.groupMetadata?.id
      )
    } else {
      // for items in the no-option column
      return targetVerticalGroup.id === MissingVerticalGroupId
    }
  })
}

/**
 * Checks whether every item is already in the target group when PWL is enabled
 */
export function isEveryItemInColumnPWL(
  queryClient: QueryClient,
  selectedItems: Array<MemexItemModel>,
  targetVerticalGroup: VerticalGroup,
) {
  const targetServerGroupId = getServerGroupIdForVerticalGroupId(queryClient, targetVerticalGroup.id)
  if (!targetServerGroupId) {
    return false
  }

  // Return false if any of the items are not in the target group
  return selectedItems.every(item => {
    return isMemexItemInGroup(queryClient, item.id, targetServerGroupId)
  })
}

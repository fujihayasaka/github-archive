import type {ColumnModel} from '../../models/column-model'
import type {MemexItemModel} from '../../models/memex-item-model'
import {resolveFieldValueEqualsFunction} from './resolver'

/**
 * Determines whether or not an item move operation would result in it still
 * being contiguous to other items with the same sort value. Useful for scenarios
 * where we have a sorted view and we want to notify a user that the operation
 * they're about to perform is invalid.
 *
 * @param itemToMove The item (card / row) that is being dragged
 * @param sortField The field to use to check sort values
 * @param sortedItems Sorted list of items being considered for the operation
 * @param overItemId The id of the item (card / row) that we're dropping over
 * @param overItemSide Whether we're dropping before or after the item
 * @returns
 */
export function isItemMovingWithinSortedValue(
  itemToMove: MemexItemModel,
  sortField: ColumnModel,
  sortedItems: Readonly<Array<MemexItemModel>>,
  overItemId: number,
  overItemSide: 'before' | 'after',
): boolean {
  const equals = resolveFieldValueEqualsFunction(sortField)

  const indexOfMovingItem = sortedItems.findIndex(i => i.id === itemToMove.id)
  let indexOfOverItem = sortedItems.findIndex(i => i.id === overItemId)
  // Check to see if we're moving an item down, and the reorder side is before. In this case,
  // we want to use the previous item for checking the sort field's value.
  // This will ensure we have the correct logic for when we're dragging to a boundary between
  // two "chunks" of sorted items.
  if (overItemSide === 'before' && indexOfOverItem > indexOfMovingItem) {
    indexOfOverItem = indexOfOverItem - 1
  }
  // Check to see if we're moving an item up, and the reorder side is after. In this case,
  // we want to use the next item for checking the sort field's value.
  // This will ensure we have the correct logic for when we're dragging to a boundary between
  // two "chunks" of sorted items.
  else if (overItemSide === 'after' && indexOfOverItem < indexOfMovingItem) {
    indexOfOverItem = indexOfOverItem + 1
  }

  const overItem = sortedItems[indexOfOverItem]
  return overItem ? equals(itemToMove, overItem) : true
}

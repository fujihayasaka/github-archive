import type {MemexProjectColumnId} from '../../api/columns/contracts/memex-column'
import type {MemexItemModel} from '../../models/memex-item-model'
import {useHasColumnData} from '../../state-providers/columns/use-has-column-data'
import {itemHasColumnLoaded} from '../../state-providers/memex-items/memex-items-data'
import {useEnabledFeatures} from '../use-enabled-features'

/**
 * Checks whether a field is loaded for a given item.
 * @param item - an item with potentially loaded fields
 * @param columnId - the id of field to check
 * @returns boolean indicating whether the field is loaded
 */
export const useIsColumnLoadedForItem = (item: MemexItemModel, columnId: MemexProjectColumnId) => {
  const {memex_table_without_limits} = useEnabledFeatures()
  if (memex_table_without_limits) {
    return itemHasColumnLoaded(item, columnId)
  }
  // It's safe to conditionally call this hook here since FF values
  // do not change during the lifetime of the app
  // eslint-disable-next-line react-compiler/react-compiler
  // eslint-disable-next-line react-hooks/rules-of-hooks
  return useIsColumnLoaded(columnId)
}

/**
 * Checks if a column has been globally loaded in the project.
 * @deprecated - When Projects Without Limits is enabled,
 * use useIsColumnLoadedForItem instead.
 */
const useIsColumnLoaded = (columnId: MemexProjectColumnId) => {
  const {hasColumnData} = useHasColumnData()
  return hasColumnData(columnId)
}

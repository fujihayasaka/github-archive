import {useCallback} from 'react'

import type {
  LocalUpdatePayload,
  RemoteUpdatePayload,
  UpdateColumnValueAction,
} from '../../api/columns/contracts/storage'
import {cancelGetAllMemexData} from '../../api/memex/api-get-all-memex-data'
import type {UpdateItemContext} from '../../api/memex/contracts'
import {apiUpdateItem} from '../../api/memex-items/api-update-item'
import {ItemType} from '../../api/memex-items/item-type'
import type {MemexItemModel, UpdateMemexItemActions} from '../../models/memex-item-model'
import {useFindLoadedFieldIdsForCurrentView} from '../columns/use-find-loaded-field-ids'
import {useHandlePaginatedDataRefresh} from '../data-refresh/use-handle-paginated-data-refresh'
import {buildMemexItemUpdateData} from '../memex-items/memex-item-helpers'
import {useSetMemexItemData} from '../memex-items/use-set-memex-item-data'
import {buildRevertForUpdate} from './column-value'
import {mapToLocalUpdate, mapToRemoteUpdate} from './column-value-payload'
import {useSetColumnValue} from './use-set-column-value'

type UpdateColumnValueHookReturnType = {
  /**
   * Updates a column in the item and reorders it at the same time by setting
   * its priority.
   *
   * WARNING: Generally, avoid using this callback directly and call it from a
   * hook that may already be provided with error/filter-matching handling, such
   * as `useUpdateItem`.
   *
   * @param model  - The item to update.
   * @param update - The update action to apply to the item.
   */
  updateColumnValueAndPriority: (
    model: MemexItemModel,
    update: UpdateMemexItemActions,
    {layoutType}: UpdateItemContext,
  ) => Promise<void>
  /**
   * Updates column values in sequential order to avoid collisions with live updates.
   *
   * @param model   - The item to update.
   * @param updates - The list of update actions to apply to the item.
   * @param previousMemexProjectItemId - The previous memex project item id.
   */
  updateMultipleSequentially: (
    model: MemexItemModel,
    updates: Array<UpdateColumnValueAction>,
    previousMemexProjectItemId?: number,
  ) => Promise<void>
}

export const useUpdateItemColumnValue = (): UpdateColumnValueHookReturnType => {
  const {setColumnValue} = useSetColumnValue()
  const {setItemData} = useSetMemexItemData()
  const {findLoadedFieldIds} = useFindLoadedFieldIdsForCurrentView()
  const loadedFieldIds = findLoadedFieldIds()
  const {handleCancelFetchData, handleRefresh} = useHandlePaginatedDataRefresh()

  const updateColumnValueAndPriority = useCallback(
    async (model: MemexItemModel, update: UpdateMemexItemActions, {layoutType, fieldIds}: UpdateItemContext = {}) => {
      if (model.contentType === ItemType.RedactedItem) {
        return
      }

      const revertLocalUpdates: Array<LocalUpdatePayload> = []
      const memexProjectColumnValues: Array<RemoteUpdatePayload> = []

      if (update.columnValues?.length) {
        // Optimistically update the value locally
        for (const columnValue of update.columnValues) {
          const localUpdate = mapToLocalUpdate(columnValue)

          // Create a copy of the update with the pre-update value to revert to if the update fails
          const revertLocalUpdate = mapToLocalUpdate(buildRevertForUpdate(columnValue, model))
          if (revertLocalUpdate) revertLocalUpdates.push(revertLocalUpdate)

          const remoteUpdate = mapToRemoteUpdate(columnValue)
          if (remoteUpdate) memexProjectColumnValues.push(remoteUpdate)

          if (localUpdate) {
            setColumnValue(model, localUpdate)
          }
        }
      }

      const previousMemexProjectItemId = update.previousMemexProjectItemId
      const updateData = buildMemexItemUpdateData(
        model.contentType,
        memexProjectColumnValues,
        previousMemexProjectItemId,
        {layoutType},
      )

      if (!updateData) {
        return
      }

      try {
        cancelGetAllMemexData()
        handleCancelFetchData()
        const {memexProjectItem, invalidateQueryCache} = await apiUpdateItem({
          memexProjectItemId: model.id,
          // Side panel items may have more fields loaded than are generally loaded in the view
          fieldIds: fieldIds ?? loadedFieldIds,
          ...updateData,
        })

        setItemData(memexProjectItem)
        if (invalidateQueryCache) {
          handleRefresh()
        }
      } catch (error) {
        for (const revertLocalUpdate of revertLocalUpdates) {
          setColumnValue(model, revertLocalUpdate)
        }
        throw error
      }
    },
    [loadedFieldIds, setColumnValue, setItemData, handleCancelFetchData, handleRefresh],
  )

  /**
   * @deprecated prefer `useBulkUpdateItemColumnValues` instead
   */
  const updateMultipleSequentially = useCallback(
    async (model: MemexItemModel, updates: Array<UpdateColumnValueAction>, previousMemexProjectItemId?: number) => {
      if (model.contentType === ItemType.RedactedItem) {
        return
      }

      const localUpdates = updates.map(mapToLocalUpdate)
      const remoteUpdates = updates.map(mapToRemoteUpdate)
      const revertLocalUpdates = updates.map(u => mapToLocalUpdate(buildRevertForUpdate(u, model)))

      return model.whileSkippingLiveUpdates(async () => {
        // Optimistically apply all updates
        for (const localUpdate of localUpdates) {
          if (localUpdate) {
            setColumnValue(model, localUpdate)
          }
        }

        let lastSuccessfulResponse
        for (const remoteUpdate of remoteUpdates) {
          if (!remoteUpdate) {
            continue
          }

          const memexProjectColumnValues = remoteUpdate ? [remoteUpdate] : undefined
          const updateData = buildMemexItemUpdateData(
            model.contentType,
            memexProjectColumnValues,
            previousMemexProjectItemId,
          )

          if (!updateData) {
            continue
          }

          try {
            cancelGetAllMemexData()
            lastSuccessfulResponse = await apiUpdateItem({
              memexProjectItemId: model.id,
              fieldIds: loadedFieldIds,
              ...updateData,
            })
          } catch {
            // Do nothing as we will revert updates later if necessary
          }
        }

        if (lastSuccessfulResponse) {
          setItemData(lastSuccessfulResponse.memexProjectItem)
          return
        }

        for (const revertLocalUpdate of revertLocalUpdates) setColumnValue(model, revertLocalUpdate)
      })
    },
    [loadedFieldIds, setColumnValue, setItemData],
  )

  return {updateColumnValueAndPriority, updateMultipleSequentially}
}

import {useCallback} from 'react'

import type {MemexProjectColumnId} from '../../api/columns/contracts/memex-column'
import {useEnabledFeatures} from '../../hooks/use-enabled-features'
import {useViews} from '../../hooks/use-views'
import {useColumnsStableContext} from './use-columns-stable-context'

type UpdateLoadedColumnsHookReturnType = {
  /**
   * Adds a particular column to our list of columns which have been loaded
   *
   * @param columnId The column id which was received from the server and should
   *                 be marked as "loaded" in the client.
   */
  updateLoadedColumns: (columnId: MemexProjectColumnId) => void
}

export const useUpdateLoadedColumns = (): UpdateLoadedColumnsHookReturnType => {
  const {addLoadedFieldId} = useColumnsStableContext()
  const updateLoadedColumns = useCallback(
    (columnId: MemexProjectColumnId) => {
      addLoadedFieldId(columnId)
    },
    [addLoadedFieldId],
  )

  return {updateLoadedColumns}
}

export const useUpdateLoadedColumnsForCurrentView = (): UpdateLoadedColumnsHookReturnType => {
  const {updateLoadedColumns: addLoadedFieldIdForProject} = useUpdateLoadedColumns()
  const {addLoadedFieldIdForCurrentView} = useViews()
  const {memex_table_without_limits} = useEnabledFeatures()
  const updateLoadedColumns = useCallback(
    (columnId: MemexProjectColumnId) => {
      if (memex_table_without_limits) {
        addLoadedFieldIdForCurrentView(columnId)
      } else {
        addLoadedFieldIdForProject(columnId)
      }
    },
    [addLoadedFieldIdForProject, addLoadedFieldIdForCurrentView, memex_table_without_limits],
  )

  return {updateLoadedColumns}
}

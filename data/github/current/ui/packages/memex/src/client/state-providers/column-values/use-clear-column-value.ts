import {useCallback} from 'react'
import type {Row} from 'react-table'

import {MemexColumnDataType, SystemColumnId} from '../../api/columns/contracts/memex-column'
import {getColumnText} from '../../components/column-detail-helpers'
import useToasts from '../../components/toasts/use-toasts'
import {assertNever} from '../../helpers/assert-never'
import {isNumber, parseColumnId} from '../../helpers/parsing'
import {useBulkUpdateItems} from '../../hooks/use-bulk-update-items'
import {isValueClearableColumn} from '../../models/column-capabilities'
import type {MemexItemModel} from '../../models/memex-item-model'
import {HistoryResources} from '../../strings'

export type ColumnInfo = {id: string; columnModel?: {dataType: MemexColumnDataType}}

/**
 * This hook provides a callback for clearing a particular column value from an
 * item.
 */
export function useClearColumnValue() {
  const {bulkUpdateSingleColumnValue: updateItems} = useBulkUpdateItems()

  const {addToast} = useToasts()

  const clearColumnValue = useCallback(
    async (column: ColumnInfo, rows: Array<Row<MemexItemModel>>): Promise<void> => {
      if (!column.columnModel) {
        // column is not associated with any data - ignore callback
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({type: 'error', message: 'You cannot delete this'})
        return
      }

      const models = rows.map(row => row.original)

      const {dataType} = column.columnModel
      const memexProjectColumnId = parseColumnId(column.id)

      if (!isValueClearableColumn(dataType)) {
        const columnAsString = getColumnText(dataType)
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'error',
          message: `${columnAsString} cannot be deleted`,
        })
        return
      }

      switch (dataType) {
        case MemexColumnDataType.Assignees: {
          const payload = {
            columnValue: {
              dataType: MemexColumnDataType.Assignees,
              value: [],
            },
          }

          return updateItems(models, payload.columnValue, HistoryResources.delete)
        }
        case MemexColumnDataType.Labels: {
          const payload = {
            columnValue: {
              dataType: MemexColumnDataType.Labels,
              value: [],
            },
          }

          return updateItems(models, payload.columnValue, HistoryResources.delete)
        }
        case MemexColumnDataType.Milestone: {
          const payload = {
            columnValue: {
              dataType: MemexColumnDataType.Milestone,
              value: undefined,
            },
          }

          return updateItems(models, payload.columnValue, HistoryResources.delete)
        }
        case MemexColumnDataType.IssueType: {
          const payload = {
            columnValue: {
              dataType: MemexColumnDataType.IssueType,
              value: undefined,
            },
          }

          return updateItems(models, payload.columnValue, HistoryResources.delete)
        }
        case MemexColumnDataType.ParentIssue: {
          const payload = {
            columnValue: {
              dataType: MemexColumnDataType.ParentIssue,
              value: undefined,
            },
          }

          return updateItems(models, payload.columnValue, HistoryResources.delete)
        }
        case MemexColumnDataType.Text:
        case MemexColumnDataType.Number:
        case MemexColumnDataType.Date:
        case MemexColumnDataType.Iteration:
          if (isNumber(memexProjectColumnId)) {
            const payload = {
              columnValue: {
                dataType,
                memexProjectColumnId,
                value: undefined,
              },
            }

            return updateItems(models, payload.columnValue, HistoryResources.delete)
          }
          break
        case MemexColumnDataType.SingleSelect:
          if (memexProjectColumnId === SystemColumnId.Status || isNumber(memexProjectColumnId)) {
            const payload = {
              columnValue: {
                memexProjectColumnId,
                dataType,
                value: undefined,
              },
            }

            return updateItems(models, payload.columnValue, HistoryResources.delete)
          }
          break
        default: {
          assertNever(dataType)
        }
      }
    },
    [updateItems, addToast],
  )

  return {clearColumnValue}
}

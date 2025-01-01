import type {Cell} from 'react-table'

import {MemexColumnDataType, type MemexProjectColumnId, SystemColumnId} from '../../api/columns/contracts/memex-column'
import type {
  GetColumnDataBySystemId,
  MemexColumnData,
  TitleColumnData,
  UpdateColumnValueAction,
} from '../../api/columns/contracts/storage'
import {ItemType} from '../../api/memex-items/item-type'
import {assertNever} from '../../helpers/assert-never'
import {
  isDateColumnValue,
  isNumber,
  isNumericColumnValue,
  isSingleSelectOrIterationColumnValue,
  isSystemColumnId,
  isTextColumnValue,
  parseDateValue,
} from '../../helpers/parsing'
import {isValueEditableColumn} from '../../models/column-capabilities'
import type {MemexItemModel} from '../../models/memex-item-model'

function getTitleColumnValue(item: MemexItemModel): TitleColumnData | null {
  const columnValue = item.columns.Title
  if (!columnValue) {
    return null
  }

  switch (columnValue.contentType) {
    case ItemType.DraftIssue: {
      return {
        memexProjectColumnId: SystemColumnId.Title,
        value: columnValue.value,
      }
    }
    case ItemType.Issue: {
      return {
        memexProjectColumnId: SystemColumnId.Title,
        value: columnValue.value,
      }
    }
    case ItemType.PullRequest: {
      return {
        memexProjectColumnId: SystemColumnId.Title,
        value: columnValue.value,
      }
    }
    case ItemType.RedactedItem: {
      return {
        memexProjectColumnId: SystemColumnId.Title,
        value: columnValue.value,
      }
    }
    default:
      return null
  }
}

const valueMismatchError = (columnId: string | number, dataType: string) =>
  new Error(`Value of column with ID "${columnId}" does not match expected type "${dataType}"`)

/** Return the revert update (the update that would return the column to its current state) for the given update. */
export function buildRevertForUpdate(update: UpdateColumnValueAction, item: MemexItemModel): UpdateColumnValueAction {
  return extractValueAndBuildUpdateAction(getColumnIdForAction(update), update.dataType, item)
}

export function buildUpdateCopyingCell(cell: Cell<MemexItemModel>): UpdateColumnValueAction | null {
  try {
    const columnModel = cell.column.columnModel
    return columnModel !== undefined
      ? extractValueAndBuildUpdateAction(columnModel.id, columnModel.dataType, cell.row.original)
      : null
  } catch {
    return null
  }
}

function getColumnIdForAction(update: UpdateColumnValueAction): MemexProjectColumnId {
  if (!isValueEditableColumn(update.dataType)) {
    throw new Error(`Cannot update column of type "${update.dataType}"`)
  }
  switch (update.dataType) {
    case MemexColumnDataType.Assignees:
      return SystemColumnId.Assignees
    case MemexColumnDataType.Labels:
      return SystemColumnId.Labels
    case MemexColumnDataType.Milestone:
      return SystemColumnId.Milestone
    case MemexColumnDataType.Repository:
      return SystemColumnId.Repository
    case MemexColumnDataType.IssueType:
      return SystemColumnId.IssueType
    case MemexColumnDataType.ParentIssue:
      return SystemColumnId.ParentIssue
    case MemexColumnDataType.Title:
      return SystemColumnId.Title
    case MemexColumnDataType.Text:
    case MemexColumnDataType.Number:
    case MemexColumnDataType.Date:
    case MemexColumnDataType.Iteration:
    case MemexColumnDataType.SingleSelect:
      return update.memexProjectColumnId
    default:
      assertNever(update)
  }
}

/**
 * Build an update that can be applied to set a row to have the same value as this row (in the column provided).=
 */
function extractValueAndBuildUpdateAction(
  columnId: MemexProjectColumnId,
  dataType: MemexColumnDataType,
  item: MemexItemModel,
): UpdateColumnValueAction {
  // I hate these repetitive massive switch statements but it's the only way to make it typesafe :(
  if (!isValueEditableColumn(dataType)) {
    throw new Error(`Cannot update column of type "${dataType}"`)
  }
  switch (dataType) {
    case MemexColumnDataType.Assignees:
      return {dataType, value: item.columns[SystemColumnId.Assignees] ?? []}

    case MemexColumnDataType.Labels:
      return {dataType, value: item.columns[SystemColumnId.Labels] ?? []}

    case MemexColumnDataType.Milestone:
      return {dataType, value: item.columns[SystemColumnId.Milestone]}

    case MemexColumnDataType.Repository:
      return {dataType, value: item.columns[SystemColumnId.Repository]}

    case MemexColumnDataType.IssueType:
      return {dataType, value: item.columns[SystemColumnId.IssueType]}

    case MemexColumnDataType.ParentIssue:
      return {dataType, value: item.columns[SystemColumnId.ParentIssue]}

    case MemexColumnDataType.Title: {
      const titleColumn = item.columns[SystemColumnId.Title]
      if (!titleColumn || titleColumn.contentType === ItemType.RedactedItem)
        throw new Error('Cannot update title of redacted item')
      return {dataType, value: titleColumn.value}
    }

    // For custom columns below, the type of model[id] is a big union so we need to verify correctness or throw

    case MemexColumnDataType.Text: {
      if (typeof columnId === 'number') {
        const columnValue = item.columns[columnId]
        if (columnValue === undefined || isTextColumnValue(columnValue))
          return {dataType, memexProjectColumnId: columnId, value: columnValue?.raw}
      }
      throw valueMismatchError(columnId, dataType)
    }

    case MemexColumnDataType.Number: {
      if (typeof columnId === 'number') {
        const columnValue = item.columns[columnId]
        if (columnValue === undefined || isNumericColumnValue(columnValue))
          return {dataType, memexProjectColumnId: columnId, value: columnValue}
      }
      throw valueMismatchError(columnId, dataType)
    }

    case MemexColumnDataType.Date: {
      if (typeof columnId === 'number') {
        const columnValue = item.columns[columnId]
        if (isDateColumnValue(columnValue)) {
          const parsedDateValue = parseDateValue(columnValue)
          if (parsedDateValue) {
            return {dataType, memexProjectColumnId: columnId, value: parsedDateValue}
            // if a parsed date value is null, set the value to undefined
          } else if (parsedDateValue === null) {
            return {dataType, memexProjectColumnId: columnId, value: undefined}
          }
        } else if (columnValue === undefined) {
          return {dataType, memexProjectColumnId: columnId, value: columnValue}
        }
      }
      throw valueMismatchError(columnId, dataType)
    }

    case MemexColumnDataType.Iteration:
      if (typeof columnId === 'number') {
        const columnValue = item.columns[columnId]
        if (columnValue === undefined || isSingleSelectOrIterationColumnValue(columnValue))
          return {dataType, memexProjectColumnId: columnId, value: columnValue}
      }
      throw valueMismatchError(columnId, dataType)

    case MemexColumnDataType.SingleSelect: {
      if (typeof columnId === 'number' || columnId === SystemColumnId.Status) {
        const columnValue = item.columns[columnId]
        if (columnValue === undefined || isSingleSelectOrIterationColumnValue(columnValue))
          return {dataType, memexProjectColumnId: columnId, value: columnValue}
      }
      throw valueMismatchError(columnId, dataType)
    }
    default:
      assertNever(dataType)
  }
}

/**
 * Use to retrieve MemexColumnData from a MemexItemModel
 *
 * @param columnId - The column id to use to retrieve the column value
 * @param item    - The MemexItemModel to retrieve a column value based on the MemexProjectColumnId
 * @returns MemexColumnData from the given MemexItemModel
 */
export function getCurrentColumnValueFromModel(
  columnId: MemexProjectColumnId,
  item: MemexItemModel,
): MemexColumnData | null {
  if (columnId === SystemColumnId.Title) {
    return getTitleColumnValue(item)
  }

  if (isSystemColumnId(columnId)) {
    return {
      memexProjectColumnId: columnId,
      value: item.columns[columnId] || null,
    } as GetColumnDataBySystemId<typeof columnId>
  }

  const memexProjectColumnId = columnId
  const value = item.columns[memexProjectColumnId] || null
  return isNumber(memexProjectColumnId) ? ({memexProjectColumnId, value} as MemexColumnData) : null
}

import type {DateValue} from '../../../../api/columns/contracts/date'
import type {MemexColumnDataType, SystemColumnId} from '../../../../api/columns/contracts/memex-column'
import type {
  DataTypeToValueMap,
  MakeOptionalIfNotArray,
  UpdateColumnValueAction,
} from '../../../../api/columns/contracts/storage'
import {type CopyableColumn, isCopyableColumn, type PasteableColumn} from '../../../../models/column-capabilities'
import type {ColumnModel} from '../../../../models/column-model'
import type {TableDataType} from '../../table-data-type'
import type {ClipboardActionTypes, ClipboardOnly_UrlColumnModel} from './constants'

/** Date is special, in that it uses a browser Date object for serialization, rather than its ServerDateValue */
type TypesWithoutDate = Exclude<CopyableColumn, typeof MemexColumnDataType.Date>

/**
 * Helper to add repositoryId when needed. This is used to validate paste actions prior to applying an update.
 * For assignees, repository can be null as it applies to draft issues.
 */
type WithRepositoryIdIfNeeded<DT extends MemexColumnDataType> = DT extends typeof MemexColumnDataType.Assignees
  ? {repositoryId: number | null}
  : DT extends
        | typeof MemexColumnDataType.Labels
        | typeof MemexColumnDataType.Milestone
        | typeof MemexColumnDataType.IssueType
        | typeof MemexColumnDataType.ParentIssue
    ? {repositoryId: number}
    : unknown

/**
 * Generate type for a specific column data type using DataTypeToValueMap
 */
type GenerateMetadataForType<DT extends MemexColumnDataType> = {
  dataType: DT
  value: MakeOptionalIfNotArray<DataTypeToValueMap[DT]>
} & WithRepositoryIdIfNeeded<DT>

type UpdateClipboardAction = {
  type: typeof ClipboardActionTypes.UPDATE_CLIPBOARD
  state: ClipboardTable
}

type ClearClipboardAction = {
  type: typeof ClipboardActionTypes.CLEAR_CLIPBOARD
}

export type ClipboardAction = UpdateClipboardAction | ClearClipboardAction

/**
 * The ClipboardContentValue context value can either be "empty" (the initial
 * state) or "populated" (the user has chosen a value to duplicate).
 */
export type ClipboardState = {type: 'empty'} | {type: 'populated'; value: ClipboardTable}

type CopyableColumnModel = Extract<ColumnModel, {dataType: CopyableColumn}>
export type ClipboardColumnModel = CopyableColumnModel | typeof ClipboardOnly_UrlColumnModel

export function isClipboardColumnModel(columnModel: ColumnModel): columnModel is CopyableColumnModel {
  return isCopyableColumn(columnModel.dataType)
}

export type ClipboardCellData = {
  repositoryId?: number
  column: ClipboardColumnModel
  row: TableDataType
}

/**
 * This type represents the supported set of values which can be moved
 * from one location to another. These are very similar to the values supported
 * in ColumnData with some additional details from the relevant project item.
 */
export type ClipboardMetadata =
  | {
      [DT in TypesWithoutDate]: GenerateMetadataForType<DT>
    }[TypesWithoutDate]
  // Add the special clipboard-only URL type that isn't in the column maps
  | {dataType: typeof ClipboardOnly_UrlColumnModel.dataType; value: string}
  | {dataType: typeof MemexColumnDataType.Date; value: DateValue | undefined}

export type ClipboardContentValue = {
  state: ClipboardState
  clipboardDispatch: React.Dispatch<ClipboardAction>
}

export type ClipboardEntry = {
  /**
   * Used when pasting outside of a project, or as a fallback value for places where the clipboard value is not
   * directly compatible (e.g. text value -> single select).
   */
  text: string
  /** Rich content for pasting into supported external software. If not provided, `text` is used. */
  html?: string
} & ClipboardMetadata

export type ClipboardContent = ClipboardEntry & {
  columnId?: number | SystemColumnId | typeof ClipboardOnly_UrlColumnModel.id
  itemId?: number
}

export type ClipboardTable = Array<Array<ClipboardContent | undefined>>

export type BaseClipboardBehavior<T extends ClipboardColumnModel> = {
  readContent: (row: TableDataType, column: T) => ClipboardEntry | undefined
}

export type PasteableClipboardBehavior<T extends ClipboardColumnModel> = BaseClipboardBehavior<T> & {
  buildUpdate: (clipboardContent: ClipboardContent | string, column: T) => UpdateColumnValueAction | undefined
}

/**
 * Defines behavior for handling clipboard operations on a table column
 * @template T - Type extending ClipboardColumnModel
 *
 * @property readContent - Function to read clipboard content from a table row and column
 * @param row - The table row data
 * @param column - The column configuration
 * @returns ClipboardEntry or undefined if no content can be read
 *
 * @property buildUpdate - Optional function to build an update action from clipboard content
 * @param clipboardContent - The content from clipboard, either structured or plain string
 * @param column - The column configuration
 * @returns UpdateColumnValueAction or undefined if no update can be built
 */

export type ClipboardColumnBehavior<T extends ClipboardColumnModel> = T['dataType'] extends PasteableColumn
  ? PasteableClipboardBehavior<T>
  : BaseClipboardBehavior<T>

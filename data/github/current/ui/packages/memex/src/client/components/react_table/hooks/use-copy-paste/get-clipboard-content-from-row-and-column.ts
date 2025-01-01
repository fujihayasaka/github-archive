import type {TableDataType} from '../../table-data-type'
import {getBehaviorForColumn} from './columns'
import {extractCellData} from './extract-cell-data'
import type {ClipboardColumnModel, ClipboardContent} from './types'

export const getClipboardContentFromRowAndColumn = (
  columnModel: ClipboardColumnModel,
  row: TableDataType,
): ClipboardContent | undefined => {
  const cellData = extractCellData(columnModel, row)
  if (!cellData) return

  const behavior = getBehaviorForColumn(columnModel)
  const clipboardContent = behavior.readContent(cellData.row, cellData.column)
  if (!clipboardContent) return

  return {
    ...clipboardContent,
    columnId: cellData.column.id,
    itemId: cellData.row.id,
  }
}

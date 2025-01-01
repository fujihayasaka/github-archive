import type {Cell} from 'react-table'

import type {TableDataType} from '../../table-data-type'
import {getBehaviorForColumn} from './columns'
import {extractCellData} from './extract-cell-data'
import {type ClipboardContent, isClipboardColumnModel} from './types'

// FIXME: Exported for tests; tests should be updated to test the hook itself but this is tricky because we can't use Playwright to assert the clipboard
export const getCellClipboardContent = (
  cell: Pick<Cell<TableDataType>, 'column' | 'row'>,
): ClipboardContent | undefined => {
  if (!cell.column.columnModel) {
    return
  }
  if (!isClipboardColumnModel(cell.column.columnModel)) {
    return
  }
  const cellData = extractCellData(cell.column.columnModel, cell.row.original)
  if (!cellData) return

  const behavior = getBehaviorForColumn(cell.column.columnModel)
  const clipboardContent = behavior.readContent(cellData.row, cellData.column)
  if (!clipboardContent) return

  return {
    ...clipboardContent,
    columnId: cellData.column.id,
    itemId: cellData.row.id,
  }
}

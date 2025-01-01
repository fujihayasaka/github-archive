import type {TableDataType} from '../../table-data-type'
import type {ClipboardCellData, ClipboardColumnModel} from './types'

export function extractCellData(columnModel: ClipboardColumnModel, row: TableDataType): ClipboardCellData | undefined {
  let repositoryId: number | undefined
  if (row.contentRepositoryId) {
    repositoryId = row.contentRepositoryId
  }

  return {repositoryId, column: columnModel, row}
}

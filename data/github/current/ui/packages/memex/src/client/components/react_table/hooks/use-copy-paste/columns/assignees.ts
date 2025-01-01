import {MemexColumnDataType} from '../../../../../api/columns/contracts/memex-column'
import {ItemType} from '../../../../../api/memex-items/item-type'
import type {AssigneesColumnModel} from '../../../../../models/column-model/system/assignees'
import type {TableDataType} from '../../../table-data-type'
import {DataTypeMismatchFailureError} from '../errors'
import type {ClipboardColumnBehavior, ClipboardContent} from '../types'

export const behavior: ClipboardColumnBehavior<AssigneesColumnModel> = {
  readContent: (row: TableDataType) => {
    const assignees = row.columns.Assignees || []
    if (row.contentType === ItemType.RedactedItem) return

    return {
      text: assignees.map(a => a.login).join(', '),
      dataType: MemexColumnDataType.Assignees,
      value: assignees,
      repositoryId: row.contentRepositoryId,
    }
  },
  buildUpdate: (content: ClipboardContent | string) => {
    if (typeof content === 'string') return // Do not allow arbitrary pasting for this data type
    if (content.dataType !== MemexColumnDataType.Assignees) throw new DataTypeMismatchFailureError()

    const users = content.value
    return {
      dataType: MemexColumnDataType.Assignees,
      value: users,
    }
  },
}

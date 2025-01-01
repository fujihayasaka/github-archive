import {MemexColumnDataType} from '../../../../../api/columns/contracts/memex-column'
import type {ReviewersColumnModel} from '../../../../../models/column-model/system/reviewers'
import type {TableDataType} from '../../../table-data-type'
import type {ClipboardColumnBehavior} from '../types'

export const behavior: ClipboardColumnBehavior<ReviewersColumnModel> = {
  readContent: (row: TableDataType) => {
    const reviews = row.columns.Reviewers
    if (!reviews || reviews.length === 0) return

    return {
      text: reviews.map(a => a.reviewer.name).join(', '),
      dataType: MemexColumnDataType.Reviewers,
      value: reviews || [],
    }
  },
}

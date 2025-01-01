import {MemexColumnDataType} from '../../../../../api/columns/contracts/memex-column'
import {ItemType} from '../../../../../api/memex-items/item-type'
import {sanitizeTextInputHtmlString} from '../../../../../helpers/sanitize'
import type {LabelsColumnModel} from '../../../../../models/column-model/system/labels'
import type {TableDataType} from '../../../table-data-type'
import {DataTypeMismatchFailureError} from '../errors'
import type {ClipboardColumnBehavior, ClipboardContent} from '../types'

export const behavior: ClipboardColumnBehavior<LabelsColumnModel> = {
  readContent: (row: TableDataType) => {
    if (row.contentType === ItemType.DraftIssue || row.contentType === ItemType.RedactedItem) return

    const labels = row.columns.Labels || []

    return {
      text: labels.map(a => a.name).join(', '),
      dataType: MemexColumnDataType.Labels,
      value: labels,
      repositoryId: row.contentRepositoryId,
      html: labels.map(label => sanitizeTextInputHtmlString(label.nameHtml)).join(', '),
    }
  },
  buildUpdate: (content: ClipboardContent | string) => {
    if (typeof content === 'string') return // Do not allow arbitrary pasting for this data type
    if (content.dataType !== MemexColumnDataType.Labels) throw new DataTypeMismatchFailureError()

    const labels = content.value
    const payload = {
      dataType: MemexColumnDataType.Labels,
      value: labels,
    }

    return payload
  },
}

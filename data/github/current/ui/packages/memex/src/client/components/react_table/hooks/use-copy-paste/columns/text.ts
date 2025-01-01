import {MemexColumnDataType} from '../../../../../api/columns/contracts/memex-column'
import {asCustomTextValue} from '../../../../../helpers/parsing'
import {sanitizeTextInputHtmlString} from '../../../../../helpers/sanitize'
import type {TextColumnModel} from '../../../../../models/column-model/custom/text'
import type {TableDataType} from '../../../table-data-type'
import type {ClipboardColumnBehavior, ClipboardContent} from '../types'

export const behavior: ClipboardColumnBehavior<TextColumnModel> = {
  readContent: (row: TableDataType, column: TextColumnModel) => {
    const customColumnValue = row.columns[column.id]
    const value = asCustomTextValue(customColumnValue) || undefined

    return {
      text: value?.raw || '',
      dataType: MemexColumnDataType.Text,
      value,
      html: value ? sanitizeTextInputHtmlString(value.html) : '',
    }
  },
  buildUpdate: (content: ClipboardContent | string, column: TextColumnModel) => {
    return {
      dataType: MemexColumnDataType.Text,
      memexProjectColumnId: column.id,
      value: typeof content === 'string' ? content : content.text,
    }
  },
}

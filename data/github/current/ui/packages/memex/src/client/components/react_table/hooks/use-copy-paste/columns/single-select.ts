import {MemexColumnDataType} from '../../../../../api/columns/contracts/memex-column'
import type {SingleSelectValue} from '../../../../../api/columns/contracts/single-select'
import {asSingleSelectValue} from '../../../../../helpers/parsing'
import {sanitizeTextInputHtmlString} from '../../../../../helpers/sanitize'
import type {SingleSelectColumnModel} from '../../../../../models/column-model/custom/single-select'
import type {StatusColumnModel} from '../../../../../models/column-model/system/status'
import type {TableDataType} from '../../../table-data-type'
import {DataTypeMismatchFailureError} from '../errors'
import type {ClipboardColumnBehavior, ClipboardContent} from '../types'

export const behavior: ClipboardColumnBehavior<SingleSelectColumnModel | StatusColumnModel> = {
  readContent: (row: TableDataType, column: SingleSelectColumnModel | StatusColumnModel) => {
    const customColumnValue = row.columns[column.id]
    const customValue = customColumnValue as SingleSelectValue
    const valueId = customValue?.id

    const options = column.settings.options || []
    const matchingOption = options.find(o => o.id === valueId)

    const raw = asSingleSelectValue(customColumnValue) || undefined
    const text = matchingOption?.name || ''

    return {
      text,
      dataType: MemexColumnDataType.SingleSelect,
      value: raw,
      html: matchingOption ? sanitizeTextInputHtmlString(matchingOption.nameHtml) : undefined,
    }
  },
  buildUpdate: (content: ClipboardContent | string, targetColumn: SingleSelectColumnModel | StatusColumnModel) => {
    if (typeof content === 'string') return // Do not allow arbitrary pasting for this data type
    let valueId: string | undefined

    if (content.dataType === MemexColumnDataType.SingleSelect && content.columnId === targetColumn.id) {
      const singleSelectValue = content.value
      valueId = singleSelectValue?.id
    } else if (content.dataType === MemexColumnDataType.Text) {
      const textValue = content.value

      const singleSelectOptions = targetColumn.settings.options
      const normalized = textValue?.raw.trim().toLowerCase()
      const matchingOption = singleSelectOptions.find(o => {
        return o.name.trim().toLowerCase() === normalized
      })

      valueId = matchingOption?.id
    }

    if (!valueId && content.value) {
      throw new DataTypeMismatchFailureError()
    }

    return {
      dataType: MemexColumnDataType.SingleSelect,
      memexProjectColumnId: targetColumn.id,
      value: valueId ? {id: valueId} : undefined,
    }
  },
}

import {MemexColumnDataType} from '../../../../../api/columns/contracts/memex-column'
import {asCustomNumberValue} from '../../../../../helpers/parsing'
import type {NumberColumnModel} from '../../../../../models/column-model/custom/number'
import type {TableDataType} from '../../../table-data-type'
import {DataTypeMismatchFailureError} from '../errors'
import type {ClipboardColumnBehavior, ClipboardContent} from '../types'

export const behavior: ClipboardColumnBehavior<NumberColumnModel> = {
  readContent: (row: TableDataType, column: NumberColumnModel) => {
    const customColumnValue = row.columns[column.id]
    const value = asCustomNumberValue(customColumnValue) || undefined

    return {
      text: value ? value.value.toString() : '',
      dataType: MemexColumnDataType.Number,
      value,
    }
  },
  buildUpdate: (content: ClipboardContent | string, column: NumberColumnModel) => {
    let number: number | undefined
    if (typeof content === 'string') {
      number = parseFloat(content)

      if (isNaN(number) && content) return
    } else if (content.dataType === MemexColumnDataType.Number) {
      const numericValue = content.value
      number = numericValue?.value
    } else if (content.dataType === MemexColumnDataType.Text) {
      number = parseFloat(content.text)
      if (isNaN(number) && content.text) throw new DataTypeMismatchFailureError()
    } else {
      number = parseFloat(content.text)
      if (isNaN(number) && content.text) throw new DataTypeMismatchFailureError()
    }

    return {
      dataType: MemexColumnDataType.Number,
      memexProjectColumnId: column.id,
      value: number ? {value: number} : undefined,
    }
  },
}

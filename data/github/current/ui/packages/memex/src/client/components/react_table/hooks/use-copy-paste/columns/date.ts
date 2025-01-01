import {MemexColumnDataType} from '../../../../../api/columns/contracts/memex-column'
import {asCustomDateString, asCustomDateValue} from '../../../../../helpers/parsing'
import type {DateColumnModel} from '../../../../../models/column-model/custom/date'
import type {TableDataType} from '../../../table-data-type'
import {DataTypeMismatchFailureError} from '../errors'
import type {ClipboardColumnBehavior, ClipboardContent} from '../types'

export const behavior: ClipboardColumnBehavior<DateColumnModel> = {
  readContent: (row: TableDataType, column: DateColumnModel) => {
    const customColumnValue = row.columns[column.id]
    const customValue = customColumnValue
    const text = asCustomDateString(customValue) || ''
    const raw = asCustomDateValue(customColumnValue) || undefined

    return {text, dataType: MemexColumnDataType.Date, value: raw}
  },
  buildUpdate: (content: ClipboardContent | string, column: DateColumnModel) => {
    if (typeof content === 'string') return // Do not allow arbitrary pasting for this data type

    if (content.dataType === MemexColumnDataType.Date) {
      const dateValue = content.value

      return {
        dataType: MemexColumnDataType.Date,
        memexProjectColumnId: column.id,
        value: dateValue ? {value: dateValue.value} : undefined,
      }
    }

    if (content?.value) throw new DataTypeMismatchFailureError()

    return {
      dataType: MemexColumnDataType.Date,
      memexProjectColumnId: column.id,
      value: undefined,
    }
  },
}

import type {IterationValue} from '../../../../../api/columns/contracts/iteration'
import {MemexColumnDataType} from '../../../../../api/columns/contracts/memex-column'
import {getAllIterations} from '../../../../../helpers/iterations'
import {sanitizeTextInputHtmlString} from '../../../../../helpers/sanitize'
import type {IterationColumnModel} from '../../../../../models/column-model/custom/iteration'
import {Resources} from '../../../../../strings'
import type {TableDataType} from '../../../table-data-type'
import {DataTypeMismatchFailureError, PasteValidationFailureError} from '../errors'
import type {ClipboardColumnBehavior, ClipboardContent} from '../types'

export const behavior: ClipboardColumnBehavior<IterationColumnModel> = {
  readContent: (row: TableDataType, column: IterationColumnModel) => {
    const customColumnValue = row.columns[column.id]
    const customValue = customColumnValue as IterationValue
    const valueId = customValue?.id

    const allIterations = getAllIterations(column)
    const matchingIteration = allIterations.find(i => i.id === valueId)
    const raw = customValue
    const text = matchingIteration?.title || ''

    return {
      text,
      dataType: MemexColumnDataType.Iteration,
      value: raw,
      html: matchingIteration ? sanitizeTextInputHtmlString(matchingIteration.titleHtml) : '',
    }
  },
  buildUpdate: (content: ClipboardContent | string, targetColumn: IterationColumnModel) => {
    if (typeof content === 'string') return // Do not allow arbitrary pasting for this data type

    let valueId: string | undefined
    if (content.dataType === MemexColumnDataType.Iteration && content.columnId === targetColumn.id) {
      const iterationValue = content.value
      valueId = iterationValue?.id
    } else if (content.dataType === MemexColumnDataType.Text) {
      const textValue = content.value

      if (!targetColumn) throw new DataTypeMismatchFailureError()

      const normalized = textValue?.raw.trim().toLowerCase()
      const matchingIteration = getAllIterations(targetColumn).find(o => {
        return o.title.trim().toLowerCase() === normalized
      })
      if (!matchingIteration && textValue) throw new PasteValidationFailureError(Resources.iterationNotFound)

      valueId = matchingIteration?.id
    }

    if (!valueId && content.value) {
      throw new DataTypeMismatchFailureError()
    }

    return {
      dataType: MemexColumnDataType.Iteration,
      memexProjectColumnId: targetColumn.id,
      value: valueId ? {id: valueId} : undefined,
    }
  },
}

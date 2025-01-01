import {MemexColumnDataType} from '../../../../../api/columns/contracts/memex-column'
import {getAllIterations} from '../../../../../helpers/iterations'
import type {IterationColumnModel} from '../../../../../models/column-model/custom/iteration'
import {Resources} from '../../../../../strings'
import {DataTypeMismatchFailureError, PasteValidationFailureError} from '../errors'
import type {ClipboardContent} from '../types'

export const buildIterationUpdateFromClipboardContent = (
  content: ClipboardContent | string,
  targetColumn: IterationColumnModel,
) => {
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
}

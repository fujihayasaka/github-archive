import {MemexColumnDataType} from '../../../../../api/columns/contracts/memex-column'
import {DataTypeMismatchFailureError} from '../errors'
import type {ClipboardContent} from '../types'

export const buildAssigneesUpdateFromClipboardContent = (content: ClipboardContent | string) => {
  if (typeof content === 'string') return // Do not allow arbitrary pasting for this data type
  if (content.dataType !== MemexColumnDataType.Assignees) throw new DataTypeMismatchFailureError()

  const users = content.value
  return {
    dataType: MemexColumnDataType.Assignees,
    value: users,
  }
}

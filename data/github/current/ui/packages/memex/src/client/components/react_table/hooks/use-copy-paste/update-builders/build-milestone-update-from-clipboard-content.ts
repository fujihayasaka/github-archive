import {MemexColumnDataType} from '../../../../../api/columns/contracts/memex-column'
import {DataTypeMismatchFailureError} from '../errors'
import type {ClipboardContent} from '../types'

export const buildMilestoneUpdateFromClipboardContent = (content: ClipboardContent | string) => {
  if (typeof content === 'string') return // Do not allow arbitrary pasting for this data type
  if (content.dataType !== MemexColumnDataType.Milestone) throw new DataTypeMismatchFailureError()

  const milestone = content.value

  return {
    dataType: MemexColumnDataType.Milestone,
    value: milestone,
  }
}

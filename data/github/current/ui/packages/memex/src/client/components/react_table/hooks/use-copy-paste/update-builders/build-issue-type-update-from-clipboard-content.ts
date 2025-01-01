import {MemexColumnDataType} from '../../../../../api/columns/contracts/memex-column'
import {DataTypeMismatchFailureError} from '../errors'
import type {ClipboardContent} from '../types'

export const buildIssueTypeUpdateFromClipboardContent = (content: ClipboardContent | string) => {
  if (typeof content === 'string') return // Do not allow arbitrary pasting for this data type
  if (content.dataType !== MemexColumnDataType.IssueType) throw new DataTypeMismatchFailureError()

  const issueType = content.value

  return {
    dataType: MemexColumnDataType.IssueType,
    value: issueType,
  }
}

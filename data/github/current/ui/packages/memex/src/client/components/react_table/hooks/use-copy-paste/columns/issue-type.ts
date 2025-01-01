import {MemexColumnDataType, SystemColumnId} from '../../../../../api/columns/contracts/memex-column'
import {ItemType} from '../../../../../api/memex-items/item-type'
import {sanitizeTextInputHtmlString} from '../../../../../helpers/sanitize'
import type {IssueTypeColumnModel} from '../../../../../models/column-model/system/issue-type'
import type {TableDataType} from '../../../table-data-type'
import {DataTypeMismatchFailureError} from '../errors'
import type {ClipboardColumnBehavior, ClipboardContent} from '../types'

export const behavior: ClipboardColumnBehavior<IssueTypeColumnModel> = {
  readContent: (row: TableDataType) => {
    if (row.contentType !== ItemType.Issue) return

    const issueType = row.columns[SystemColumnId.IssueType]

    return {
      text: issueType ? issueType.name : '',
      dataType: MemexColumnDataType.IssueType,
      value: issueType,
      repositoryId: row.contentRepositoryId,
      html: issueType ? sanitizeTextInputHtmlString(issueType.name) : '',
    }
  },
  buildUpdate: (content: ClipboardContent | string) => {
    if (typeof content === 'string') return // Do not allow arbitrary pasting for this data type
    if (content.dataType !== MemexColumnDataType.IssueType) throw new DataTypeMismatchFailureError()

    const issueType = content.value

    return {
      dataType: MemexColumnDataType.IssueType,
      value: issueType,
    }
  },
}

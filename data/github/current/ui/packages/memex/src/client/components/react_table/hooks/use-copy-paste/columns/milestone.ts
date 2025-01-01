import {MemexColumnDataType} from '../../../../../api/columns/contracts/memex-column'
import {ItemType} from '../../../../../api/memex-items/item-type'
import {sanitizeTextInputHtmlString} from '../../../../../helpers/sanitize'
import type {MilestoneColumnModel} from '../../../../../models/column-model/system/milestone'
import type {TableDataType} from '../../../table-data-type'
import {DataTypeMismatchFailureError} from '../errors'
import type {ClipboardColumnBehavior, ClipboardContent} from '../types'

export const behavior: ClipboardColumnBehavior<MilestoneColumnModel> = {
  readContent: (row: TableDataType) => {
    if (row.contentType === ItemType.DraftIssue || row.contentType === ItemType.RedactedItem) return

    const milestone = row.columns.Milestone

    return {
      text: milestone ? milestone.title : '',
      dataType: MemexColumnDataType.Milestone,
      value: milestone,
      repositoryId: row.contentRepositoryId,
      // Disabling the lint rule "github/unescaped-html-literal" as we are explicitly sanitizing the output here
      // and the milestone URL is an internal URL that we control
      // eslint-disable-next-line github/unescaped-html-literal
      html: milestone ? `<a href="${milestone.url}">${sanitizeTextInputHtmlString(milestone.title)}</a>` : '',
    }
  },
  buildUpdate: (content: ClipboardContent | string) => {
    if (typeof content === 'string') return // Do not allow arbitrary pasting for this data type
    if (content.dataType !== MemexColumnDataType.Milestone) throw new DataTypeMismatchFailureError()

    const milestone = content.value

    return {
      dataType: MemexColumnDataType.Milestone,
      value: milestone,
    }
  },
}

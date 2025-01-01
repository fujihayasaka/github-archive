import {MemexColumnDataType} from '../../../../../api/columns/contracts/memex-column'
import type {LinkedPullRequestsColumnModel} from '../../../../../models/column-model/system/linked-pull-requests'
import type {TableDataType} from '../../../table-data-type'
import type {ClipboardColumnBehavior} from '../types'

export const behavior: ClipboardColumnBehavior<LinkedPullRequestsColumnModel> = {
  readContent: (row: TableDataType) => {
    const linkedPullRequests = row.columns['Linked pull requests']
    if (!linkedPullRequests || linkedPullRequests.length === 0) return

    return {
      text: linkedPullRequests.map(pr => pr.url).join(', '),
      dataType: MemexColumnDataType.LinkedPullRequests,
      value: linkedPullRequests,
      html:
        // Disabling the lint rule "github/unescaped-html-literal" as the URL is an internal URL that we control
        // and the number should not have any potential for injection
        // eslint-disable-next-line github/unescaped-html-literal
        linkedPullRequests.map(pr => `<a href="${pr.url}">#${pr.number}</a>`).join(', '),
    }
  },
}

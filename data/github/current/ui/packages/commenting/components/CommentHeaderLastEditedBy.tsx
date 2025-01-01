import {MarkdownLastEditedBy} from '@github-ui/markdown-edit-history-viewer/MarkdownLastEditedBy'
import {useMarkdownEditHistoryViewerQuery} from '@github-ui/markdown-edit-history-viewer/use-markdown-edit-history-viewer-query'

export function CommentHeaderLastEditedBy({id}: {id: string}) {
  const data = useMarkdownEditHistoryViewerQuery({id})
  return data ? <MarkdownLastEditedBy editInformation={data} includeSeparator /> : null
}

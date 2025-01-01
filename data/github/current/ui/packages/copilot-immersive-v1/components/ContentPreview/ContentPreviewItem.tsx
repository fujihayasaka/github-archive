import {ErrorBoundary} from '@github-ui/react-core/error-boundary'

import {ErrorFallback} from '../ErrorFallback'
import type {PreviewableContent} from './content-preview-types'
import {CreateIssuePreview} from './create-issue-preview/CreateIssuePreview'
import {FilePreview} from './FilePreview'
import {ImagePreview} from './ImagePreview'
import {IssuePreview} from './IssuePreview'

interface ContentPreviewItemProps {
  isOpening: boolean
  onClose: (closePreview?: boolean) => void
  previewItem: PreviewableContent
}

export function ContentPreviewItem({isOpening, onClose, previewItem}: ContentPreviewItemProps) {
  let item = null
  switch (previewItem.type) {
    case 'file':
      item = <FilePreview isPreviewOpening={isOpening} file={previewItem} onClose={onClose} />
      break
    case 'issue':
      item = <IssuePreview isPreviewOpening={isOpening} issue={previewItem} onClose={onClose} />
      break
    case 'new-issue':
      item = <CreateIssuePreview isPreviewOpening={isOpening} issue={previewItem} onClose={onClose} />
      break
    case 'image':
      item = <ImagePreview image={previewItem} />
      break
  }

  return item ? (
    <ErrorBoundary fallback={<ErrorFallback regionName="This workbench item" />}>{item}</ErrorBoundary>
  ) : null
}

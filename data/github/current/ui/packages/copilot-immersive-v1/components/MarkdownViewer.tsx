import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {MarkdownRenderer, type MarkdownRendererProps} from '@github-ui/copilot-markdown'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useMemo, useRef} from 'react'

import {ContentPreviewBlockContext} from '../markdown-extensions/ContentPreviewBlockContext'
import fileViewExtension from '../markdown-extensions/file-blocks/file-blocks'
import createIssueBlockExtension from '../markdown-extensions/issue-blocks/create-issue-blocks-extension'
import issueLinkBlockExtension from '../markdown-extensions/issue-blocks/issue-link-block-extension'
import issueListBlockExtension from '../markdown-extensions/issue-blocks/issue-list-blocks-extension'

interface MarkdownViewerProps
  extends Omit<MarkdownRendererProps, 'onOpenFile'>,
    Omit<ContentPreviewBlockContext, 'hasAutoOpenedPreviewPaneRef'> {}

export const MarkdownViewer = ({
  messageId,
  messageIndex,
  messageTimestamp,
  autoOpenPreviewPane,
  markdown,
  ...rendererProps
}: MarkdownViewerProps) => {
  const hasAutoOpenedPreviewPaneRef = useRef(false)
  const immersiveCreateIssue = useFeatureFlag('copilot_immersive_create_issue')
  const extensions = useMemo(() => {
    const fileBlocksInMessage: string[] = []
    let result = [...(rendererProps.extensions ?? []), fileViewExtension(fileBlocksInMessage)]
    if (copilotFeatureFlags.immersiveIssuePreview) {
      result = [...result, issueLinkBlockExtension(), issueListBlockExtension()]
    }
    if (immersiveCreateIssue) {
      result = [...result, createIssueBlockExtension()]
    }
    return result
  }, [immersiveCreateIssue, rendererProps.extensions])

  return (
    <ContentPreviewBlockContext.Provider
      value={useMemo(
        () => ({messageId, messageIndex, messageTimestamp, autoOpenPreviewPane, markdown, hasAutoOpenedPreviewPaneRef}),
        [messageId, messageIndex, messageTimestamp, autoOpenPreviewPane, markdown, hasAutoOpenedPreviewPaneRef],
      )}
    >
      <MarkdownRenderer {...rendererProps} markdown={markdown} extensions={extensions} chatMode="immersive" />
    </ContentPreviewBlockContext.Provider>
  )
}

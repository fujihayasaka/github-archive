import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {MarkdownRenderer, type MarkdownRendererProps} from '@github-ui/copilot-markdown'
import type {CopilotMarkdownExtension} from '@github-ui/copilot-markdown/extension'
import {clsx} from 'clsx'
import {useMemo} from 'react'

import {ContentPreviewBlockContext} from '../../markdown-extensions/ContentPreviewBlockContext'
import fileViewExtension from '../../markdown-extensions/file-blocks/file-blocks'
import styles from './MarkdownViewer.module.css'

interface MarkdownViewerProps extends Omit<MarkdownRendererProps, 'onOpenFile'> {
  /** Current message ID. */
  messageId: string
  /** True if the content is currently streaming. */
  isStreaming?: boolean
}

export const MarkdownViewer = ({isStreaming, messageId, ...rendererProps}: MarkdownViewerProps) => {
  const extensions = useMemo(() => {
    const result: CopilotMarkdownExtension[] = []

    if (copilotFeatureFlags.immersiveFilePreview) result.push(fileViewExtension())

    return result
  }, [])

  return (
    <ContentPreviewBlockContext.Provider value={useMemo(() => ({messageId}), [messageId])}>
      <MarkdownRenderer
        className={clsx(isStreaming && styles.streamingContainer)}
        extensions={extensions}
        {...rendererProps}
      />
    </ContentPreviewBlockContext.Provider>
  )
}

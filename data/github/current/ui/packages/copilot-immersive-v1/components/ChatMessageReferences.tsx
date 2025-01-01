import {ChatMessageReferenceTokens} from '@github-ui/copilot-chat/components/ChatReferences'
import type {CopilotChatReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useCallback} from 'react'

import {makeItemFromFileReference, type PreviewableContent} from './ContentPreview/content-preview-types'
import {useContentPreview} from './ContentPreview/ContentPreviewContext'

interface ChatReferenceTokensProps {
  className?: string
  messageID: string
  messageTimestamp: string
  references: CopilotChatReference[]
  size: 'small' | 'medium'
}

export function ChatMessageReferences({
  className,
  messageID,
  messageTimestamp,
  references,
  size,
}: ChatReferenceTokensProps) {
  const {openPreviewPane, openItem, updateItem} = useContentPreview()

  const onClick = useCallback(
    (event: React.MouseEvent<HTMLAnchorElement>, reference: CopilotChatReference) => {
      // if the reference is one we can show in the browser, do
      let item: PreviewableContent
      if (reference.type === 'file') {
        item = makeItemFromFileReference(reference, messageID, messageTimestamp)
      } else {
        return
      }

      event.preventDefault()
      updateItem(item)
      openItem(item.id)
      openPreviewPane()
    },
    [messageID, messageTimestamp, openPreviewPane, openItem, updateItem],
  )

  return (
    <ChatMessageReferenceTokens
      references={references}
      onClickReference={onClick}
      size={size}
      className={className}
      align="right"
    />
  )
}

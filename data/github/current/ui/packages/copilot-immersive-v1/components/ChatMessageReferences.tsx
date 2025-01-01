import {ChatMessageReferenceTokens} from '@github-ui/copilot-chat/components/ChatReferences'
import type {CopilotChatReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useEffect} from 'react'

import {useOnReferenceSelect, type UseOnReferenceSelectProps} from '../hooks/use-on-reference-select'
import {getItemVersionForReference, makeVersionedItemFromReference} from './ContentPreview/content-preview-types'
import {useContentPreview} from './ContentPreview/ContentPreviewContext'

interface ChatReferenceTokensProps extends UseOnReferenceSelectProps {
  className?: string
  references: CopilotChatReference[]
  size: 'small' | 'medium'
}

export function ChatMessageReferences({
  className,
  messageId,
  messageIndex,
  messageTimestamp,
  references,
  size,
}: ChatReferenceTokensProps) {
  const onClick = useOnReferenceSelect({messageId, messageIndex, messageTimestamp})

  const {updateItem, versionedItems} = useContentPreview()

  // Even though we updateItem on click, we still need to updateItem on render to populate the history on load
  useEffect(() => {
    for (const ref of references) {
      const item = makeVersionedItemFromReference({ref, messageIndex, messageId, timestamp: messageTimestamp})
      if (item != null) updateItem(item)
    }
  }, [messageId, messageIndex, messageTimestamp, references, updateItem])

  return (
    <ChatMessageReferenceTokens
      references={references}
      onClickReference={onClick}
      size={size}
      className={className}
      getReferenceVersion={reference => getItemVersionForReference(reference, messageIndex, versionedItems)}
    />
  )
}

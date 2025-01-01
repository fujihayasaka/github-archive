import {ChatImage} from '@github-ui/copilot-chat/components/ChatImage'
import {sendEvent} from '@github-ui/hydro-analytics'
import {memo, useCallback, useEffect} from 'react'

import {useContentPreview} from './ContentPreview/ContentPreviewContext'

export interface ChatImageAttachmentProps {
  messageId: string
  src: string
  alt: string
  name: string
}

const ChatImageAttachmentUnmemoized = ({messageId, src, alt, name}: ChatImageAttachmentProps) => {
  const {openPreviewPane, openItem, updateItem} = useContentPreview()

  // Since name isn't guaranteed to be unique, we use the message ID as a unique identifier
  // This will likely need some adjustments when we transition to supporting multiple images per message.
  const id = `image:${messageId}` as const

  const onClick = useCallback(
    (event: React.MouseEvent<HTMLAnchorElement>) => {
      if (event.metaKey || event.ctrlKey) return

      sendEvent('dotcom_chat.activate', {target: 'BROWSER_IMAGE_OPENED', mode: 'immersive'})

      openItem(id)
      openPreviewPane()

      event.preventDefault()
    },
    [id, openPreviewPane, openItem],
  )

  useEffect(() => {
    updateItem({
      altText: alt,
      id,
      messageId,
      name,
      type: 'image',
      url: src,
    })
  }, [id, alt, messageId, name, src, updateItem])

  return <ChatImage src={src} alt={alt} onClick={onClick} useOverlay />
}

export const ChatImageAttachment = memo(ChatImageAttachmentUnmemoized)

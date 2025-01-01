import {ChatImage} from '@github-ui/copilot-chat/components/ChatImage'
import type {CopilotChatMode} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {sendEvent} from '@github-ui/hydro-analytics'
import {memo, useCallback, useEffect} from 'react'

import styles from './ChatImageAttachment.module.css'
import {useContentPreview} from './ContentPreview/ContentPreviewContext'

export interface ChatImageAttachmentProps {
  messageId: string
  src: string
  alt: string
  name: string
  mode: CopilotChatMode
  squareView?: boolean
}

const ChatImageAttachmentUnmemoized = ({messageId, src, alt, name, mode, squareView}: ChatImageAttachmentProps) => {
  const {openPreviewPane, openItem, updateItem} = useContentPreview()

  // Since name isn't guaranteed to be unique, we append the message ID as a unique identifier
  const id = `image:${src}` as const

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

  return (
    <div className={styles.imageAttachment}>
      <ChatImage src={src} alt={alt} onClick={onClick} mode={mode} useOverlay squareView={squareView} />
    </div>
  )
}

export const ChatImageAttachment = memo(ChatImageAttachmentUnmemoized)

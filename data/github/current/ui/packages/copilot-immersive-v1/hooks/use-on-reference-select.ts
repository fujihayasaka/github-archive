import type {CopilotChatReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useCallback} from 'react'

import {
  makeItemFromFileReference,
  makeItemFromIssueReference,
  makeVersionedItemFromReference,
  type PreviewableContent,
} from '../components/ContentPreview/content-preview-types'
import {useContentPreview} from '../components/ContentPreview/ContentPreviewContext'

export interface UseOnReferenceSelectProps {
  messageId?: string
  messageIndex: number
  messageTimestamp?: string
}

export function useOnReferenceSelect({messageId, messageIndex, messageTimestamp}: UseOnReferenceSelectProps) {
  const {openPreviewPane, openItem, updateItem} = useContentPreview()

  return useCallback(
    (ref: CopilotChatReference, event?: React.MouseEvent<HTMLAnchorElement>) => {
      // if the reference is one we can show in the browser, do
      let item: PreviewableContent
      switch (ref.type) {
        case 'file':
          item = makeItemFromFileReference(ref, messageId, messageTimestamp)
          break
        case 'thread-scoped-file':
          item = makeVersionedItemFromReference({ref, messageIndex, messageId, timestamp: messageTimestamp})
          break
        case 'draft-issue':
          item = makeVersionedItemFromReference({ref, messageIndex, messageId})
          break
        case 'issue':
          item = makeItemFromIssueReference(ref, messageId)
          break
        default:
          return
      }

      event?.preventDefault()
      updateItem(item)
      openItem(item.id)
      openPreviewPane()
    },
    [messageId, messageIndex, messageTimestamp, openPreviewPane, openItem, updateItem],
  )
}

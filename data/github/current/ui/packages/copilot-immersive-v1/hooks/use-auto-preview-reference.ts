import {referenceID} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useEffect, useMemo} from 'react'
import {useLocation, useSearchParams} from 'react-router-dom'

import {useOnReferenceSelect} from './use-on-reference-select'

// Extract URL search parameters for reference preview
function useReferenceSearchParams() {
  const location = useLocation()

  return useMemo(() => {
    const searchParams = new URLSearchParams(location.search)
    const referenceId = searchParams.get('reference_id')
    const messageIndexParam = searchParams.get('message_index')
    let messageIndex: number | null = null

    if (messageIndexParam !== null) {
      const parsedIndex = parseInt(messageIndexParam, 10)
      if (!isNaN(parsedIndex)) {
        messageIndex = parsedIndex
      }
    }

    return {
      referenceId,
      messageIndex,
    }
  }, [location.search])
}

export function useAutoPreviewReference() {
  const chatState = useChatState()
  const {referenceId, messageIndex} = useReferenceSearchParams()
  const [, setSearchParams] = useSearchParams()

  const messages = useMemo(() => {
    return chatState.messages ?? []
  }, [chatState.messages])

  const message = useMemo(() => {
    if (messageIndex !== null && messageIndex >= 0 && messageIndex < messages.length) {
      return messages[messageIndex]
    }
    return null
  }, [messages, messageIndex])

  const references = useMemo(() => {
    return message?.references ?? chatState.currentReferences ?? []
  }, [message?.references, chatState.currentReferences])

  const reference = useMemo(() => {
    if (!referenceId || !references.length) {
      return null
    }
    return references.find(ref => referenceID(ref) === referenceId) ?? null
  }, [referenceId, references])

  const onReferenceSelect = useOnReferenceSelect({
    messageIndex: messageIndex ?? messages.length,
    messageId: message?.id,
    messageTimestamp: message?.createdAt,
  })

  useEffect(() => {
    if (!reference) return

    onReferenceSelect(reference)

    // Clear the params after previewing
    setSearchParams(searchParams => {
      const newSearchParams = new URLSearchParams(searchParams)
      newSearchParams.delete('reference_id')
      newSearchParams.delete('message_index')
      return newSearchParams
    })
  }, [reference, onReferenceSelect, setSearchParams])
}

import {useEntitlement} from '@github-ui/copilot-chat/components/quota/EntitlementContext'
import {useSelectedCustomCopilotId} from '@github-ui/copilot-chat/hooks/use-selected-custom-copilot-id'
import type {CopilotChatRepo} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/utils/CopilotChatManagerContext'
import {getSelectedThread} from '@github-ui/copilot-chat/utils/get-selected-thread'
import {useCallback} from 'react'

import {makeVersionedItemFromReference} from '../components/ContentPreview/content-preview-types'
import {useContentPreview} from '../components/ContentPreview/ContentPreviewContext'
import {useIsSharedThread} from './use-is-shared-thread'
import {useRouteThreadId} from './use-route-thread-id'

/**
 * Custom hook that provides the handleUserSubmit function for chat interactions
 * @param currentTopicRef - React ref containing the current topic
 * @param nextMessageIndex - The index of the next message in the conversation
 * @returns handleUserSubmit function that can be used to send user messages
 */
export function useHandleMessageSubmit(
  currentTopicRef: React.MutableRefObject<CopilotChatRepo | undefined>,
  nextMessageIndex: number,
) {
  const state = useChatState()
  const {currentReferences, context} = state
  const manager = useChatManager()
  const {reloadQuota} = useEntitlement()
  const thread = getSelectedThread(state)
  const {updateItem} = useContentPreview()
  const isSharedThread = useIsSharedThread()
  const threadIdFromRoute = useRouteThreadId()
  const customCopilotId = useSelectedCustomCopilotId()

  return useCallback(
    async (content: string) => {
      reloadQuota()

      const trimmedContent = content.trim()
      if (trimmedContent === '') return

      // Mark content preview items that correspond to the references as not user-edited so that they don't automatically
      // get closed when the chat reducer clears the currentReferences.
      for (const ref of currentReferences) {
        const item = makeVersionedItemFromReference({ref, messageIndex: nextMessageIndex})
        if (item != null) updateItem({...item, isUserEdited: false})
      }

      const chatMessageParams = {
        thread,
        content,
        references: currentReferences,
        topic: currentTopicRef.current,
        context,
        customInstructions: state.customInstructions,
        model: state.model,
        customCopilotId,
        skillOptions: state.skillOptions,
      }

      if (isSharedThread) {
        const duplicate = await manager.continueSharedThread(threadIdFromRoute)

        if (duplicate) {
          const {thread: newThread, messages: newMessages} = duplicate
          const parentMessageId = newMessages.at(-1)?.id
          await manager.sendChatMessage({...chatMessageParams, thread: newThread, parentMessageId})
        }
      } else {
        await manager.sendChatMessage(chatMessageParams)
      }
    },
    [
      reloadQuota,
      thread,
      currentReferences,
      context,
      state.customInstructions,
      state.model,
      state.skillOptions,
      customCopilotId,
      isSharedThread,
      manager,
      threadIdFromRoute,
      nextMessageIndex,
      updateItem,
      currentTopicRef,
    ],
  )
}

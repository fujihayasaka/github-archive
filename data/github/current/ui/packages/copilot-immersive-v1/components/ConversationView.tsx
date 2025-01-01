import {useEntitlement} from '@github-ui/copilot-chat/components/quota/EntitlementContext'
import {useSelectedCustomCopilotId} from '@github-ui/copilot-chat/hooks/use-selected-custom-copilot-id'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {copilotLocalStorage} from '@github-ui/copilot-chat/utils/copilot-local-storage'
import {useChatState, useChatStateValues} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/utils/CopilotChatManagerContext'
import {findCustomCopilot} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {useEffect, useMemo, useRef} from 'react'

import {useHandleMessageSubmit} from '../hooks/use-handle-message-submit'
import {useIsSharedThread} from '../hooks/use-is-shared-thread'
import {ChatInputContainer} from './ChatInputContainer'
import {DragDropProvider} from './DragDropContext'
import {ErrorFallback} from './ErrorFallback'
import {Header} from './Header'
import {ImmersiveChat} from './ImmersiveChat'
import styles from './Layout.module.css'
import {NewConversation} from './NewConversation/NewConversation'
import {QuotaExceededEmptyState} from './Quota/QuotaExceededEmptyState'
import {SpaceConversationBanner, useSpaceConversationStatus} from './Spaces/SpaceConversationBanner'

interface ConversationViewProps {
  isMobile: boolean
  textAreaRef: React.RefObject<HTMLTextAreaElement>
  isSidebarOpen?: boolean
}

function ConversationViewInner({isMobile, textAreaRef, isSidebarOpen}: ConversationViewProps) {
  const state = useChatState()
  const {messages, messagesLoading, threadsLoading} = state
  const manager = useChatManager()
  const {model} = useChatStateValues('model')
  const wholeAreaDragDrop = copilotFeatureFlags.attachImagesImmersive && copilotFeatureFlags.wholeAreaDragDrop
  const {chatQuotaExceeded} = useEntitlement()
  const customCopilotId = useSelectedCustomCopilotId()
  const customCopilotExists = Boolean(findCustomCopilot(state.customCopilots, customCopilotId))
  const {variant: spaceViewVariant, customCopilot} = useSpaceConversationStatus(customCopilotId, state.selectedThreadID)
  const currentTopicRef = useRef(state.currentTopic)
  const isSharedThread = useIsSharedThread()
  const showChatInput = !spaceViewVariant || customCopilotExists

  const hasEntrypointMessage = useMemo(
    () => !state.selectedThreadID && copilotLocalStorage.getEntrypointMessage(),
    [state.selectedThreadID],
  )
  const shouldShowNewConversation = useMemo(() => {
    if (
      state.selectedThreadID || // If there's a selected thread, we know it's not a new conversation
      hasEntrypointMessage || // If there's an entrypoint message, kick off chat right away
      customCopilotId || // Custom copilots are currently still handled in the ImmersiveChat, should probably be moved up to Layout
      chatQuotaExceeded || // Don't show when quota is exceeded because we handle that in the ImmersiveChat
      messagesLoading.state === 'error' || // Don't show if there's an error state because we do show the input at the bottom then
      threadsLoading.state === 'error'
    ) {
      return false
    }

    return true
  }, [
    state.selectedThreadID,
    hasEntrypointMessage,
    customCopilotId,
    chatQuotaExceeded,
    messagesLoading.state,
    threadsLoading.state,
  ])

  const nextMessageIndex = messages.length

  const handleUserSubmit = useHandleMessageSubmit(currentTopicRef, nextMessageIndex)

  useEffect(() => {
    currentTopicRef.current = state.currentTopic
  }, [state.currentTopic])

  useEffect(() => {
    const message: string | null = copilotLocalStorage.getEntrypointMessage()
    if (message && !chatQuotaExceeded) {
      copilotLocalStorage.setEntrypointMessage(null)
      // eslint-disable-next-line @eslint-react/web-api/no-leaked-timeout
      setTimeout(() => {
        void handleUserSubmit(message)
      }, 100)
    }
  }, [handleUserSubmit, chatQuotaExceeded])

  const content = (
    <>
      <Header isSidebarOpen={isSidebarOpen} />
      {!state.selectedThreadID && chatQuotaExceeded ? (
        <QuotaExceededEmptyState />
      ) : (
        <>
          <div className={styles.content}>
            {shouldShowNewConversation ? (
              <NewConversation
                textAreaRef={textAreaRef}
                handleUserSubmit={handleUserSubmit}
                nextMessageIndex={nextMessageIndex}
              />
            ) : (
              <ImmersiveChat inputRef={textAreaRef} isMobile={isMobile} onSubmit={handleUserSubmit} />
            )}
          </div>
          {(!isSharedThread || copilotFeatureFlags.copilotDuplicateThread) && !shouldShowNewConversation && (
            <div className={styles.footer}>
              {spaceViewVariant && (
                <div className={styles.spaceBannerContainer}>
                  <SpaceConversationBanner variant={spaceViewVariant} customCopilot={customCopilot} />
                </div>
              )}
              {showChatInput && (
                <ChatInputContainer
                  textAreaRef={textAreaRef}
                  handleUserSubmit={handleUserSubmit}
                  nextMessageIndex={nextMessageIndex}
                />
              )}
            </div>
          )}
        </>
      )}
    </>
  )

  return wholeAreaDragDrop ? (
    <DragDropProvider model={model} state={state} manager={manager}>
      {content}
    </DragDropProvider>
  ) : (
    content
  )
}

export function ConversationView(props: ConversationViewProps) {
  return (
    <ErrorBoundary fallback={<ErrorFallback regionName="This conversation" />}>
      <ConversationViewInner {...props} />
    </ErrorBoundary>
  )
}

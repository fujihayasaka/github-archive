import {ChatMessagesGroup, groupChatMessages} from '@github-ui/copilot-chat/components/ChatMessagesGroup'
import {ChatScrollContainer, useChatScroll} from '@github-ui/copilot-chat/components/ChatScrollContainer'
import {MenuPortalContainer, MessagesPortalContainer} from '@github-ui/copilot-chat/components/PortalContainerUtils'
import {useChat} from '@github-ui/copilot-chat/hooks/use-chat'
import {usePlugin} from '@github-ui/copilot-chat/plugin/registry'
import {threadName as getThreadName} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {getActiveMessages} from '@github-ui/copilot-chat/utils/copilot-chat-subthreading-helpers'
import {type CopilotChatMessage, NullMessageId} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {copilotLocalStorage} from '@github-ui/copilot-chat/utils/copilot-local-storage'
import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/utils/CopilotChatManagerContext'
import {isCopilotSpacePath, isValidCopilotSpacePath} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {ArrowDownIcon} from '@primer/octicons-react'
import {IconButton, Link} from '@primer/react'
import {clsx} from 'clsx'
import type React from 'react'
import {useMemo} from 'react'

import {useIsSharedThread} from '../hooks/use-is-shared-thread'
import {ChatMessage} from './ChatMessage'
import {ConversationLoader} from './ConversationLoader'
import {EmptyState} from './EmptyState'
import {ErrorState} from './ErrorState'
import styles from './ImmersiveChat.module.css'
import {SpacesHomePageState} from './Spaces/SpacesHomePageState'
import {TimelineEditEntriesForCurrentEdits} from './TimelineEditEntry'

interface ImmersiveChatProps {
  inputRef?: React.RefObject<HTMLTextAreaElement>
  panelWidth?: number
  isMobile: boolean
  onSubmit?: (text: string) => Promise<void>
}

const Messages = ({inputRef, panelWidth, isMobile}: ImmersiveChatProps) => {
  const {scrollToBottom} = useChatScroll()
  const state = useChatState()
  const {streamingMessage, isWaitingOnCopilot, messages: completedMessages, selectedThreadID} = state

  const manager = useChatManager()
  const thread = manager.getSelectedThread(state)
  const threadName = getThreadName(thread)
  const sharedMessageId = thread?.sharedMessageID

  const messages = useMemo(() => {
    const nullMessage: CopilotChatMessage = {
      id: NullMessageId,
      role: 'assistant',
      content: '',
      createdAt: '',
      threadID: selectedThreadID || '',
      references: [],
      clientSide: true,
      messageIndex: -1,
    }

    let activeMessages = completedMessages
    if (copilotFeatureFlags.immersiveSubthreading) {
      activeMessages = getActiveMessages(completedMessages)
    }

    if (isWaitingOnCopilot) {
      return [...activeMessages, streamingMessage ?? nullMessage]
    }

    return activeMessages
  }, [completedMessages, streamingMessage, isWaitingOnCopilot, selectedThreadID])

  // Instant scroll to bottom on mount
  useLayoutEffect(() => scrollToBottom('instant'), [scrollToBottom])

  const groupedMessages = groupChatMessages(messages)

  const firstReplyId = messages.find(message => message.role === 'assistant')?.id

  return (
    <div>
      <div className="sr-only">
        <h1>Copilot Chat</h1>
        <h2>{threadName}</h2>
      </div>
      {groupedMessages.map((group, i) => (
        // `message.id` is not a stable identifier because a temporary message is created locally while we
        // wait for CAPI. The ID of this message isn't the same as the message that is returned by CAPI.
        // Messages within a conversation cannot be reordered so the index should be safe to use.
        // eslint-disable-next-line @eslint-react/no-array-index-key
        <ChatMessagesGroup key={i} isLastGroup={i === groupedMessages.length - 1}>
          {group.map((message, j) => {
            let messageIndex: number
            if (copilotFeatureFlags.immersiveSubthreading) {
              // -1 indicates a streaming message; assign it to what it will become
              messageIndex = (message.messageIndex === -1 ? completedMessages.length : message.messageIndex) || j
            } else {
              messageIndex = j
            }

            return (
              <ChatMessage
                // `message.id` is not a stable identifier because a temporary message is created locally while we
                // wait for CAPI. The ID of this message isn't the same as the message that is returned by CAPI.
                // Messages within a conversation cannot be reordered so the message's index within the thread
                // should be safe to use.
                key={messageIndex}
                isLatestMessage={i === groupedMessages.length - 1 && j === group.length - 1}
                isSharedMessage={message.id === sharedMessageId}
                isFirstReply={message.id === firstReplyId}
                message={message}
                messageIndex={messageIndex}
                inputRef={inputRef}
                panelWidth={panelWidth}
                isStreaming={message.id === streamingMessage?.id}
                autoOpenPreviewPane={!isMobile}
              />
            )
          })}
          {i === groupedMessages.length - 1 && <TimelineEditEntriesForCurrentEdits />}
        </ChatMessagesGroup>
      ))}
    </div>
  )
}

const FailedToLoadThreadError = () => {
  return (
    <ErrorState
      title="Conversation failed to load"
      description={
        <>
          <Link
            href=""
            onClick={e => {
              e.preventDefault()
              window.location.reload()
            }}
            inline
          >
            Reload the page
          </Link>{' '}
          to try again.
        </>
      }
    />
  )
}

const NotFoundError = () => {
  const {messagesLoading, ssoOrganizations} = useChatState()
  const ssoOrgNames = messagesLoading.missingOrgIds
    ?.map(id => String(id))
    .map(id => ssoOrganizations?.find(org => org.id === id)?.login)
    .filter((login: string | undefined): login is string => !!login)
  const message =
    ssoOrgNames && ssoOrgNames.length > 0
      ? "This URL may be incorrect, you're signed out of your organization or the conversation may have been deleted."
      : 'This URL may be incorrect or the conversation may have been deleted.'

  return <ErrorState title="Conversation not found" description={message} ssoOrgs={ssoOrgNames} />
}

const SharedThreadNotFound = () => (
  <ErrorState
    title="Shared conversation not found"
    description="This URL may be incorrect or the conversation may have been deleted."
  />
)

const SpaceNotFound = () => (
  <ErrorState title="Space not found" description="This URL may be incorrect or the space may have been deleted." />
)

export const ImmersiveChat = ({inputRef, panelWidth, isMobile, onSubmit}: ImmersiveChatProps) => {
  const state = useChatState()
  const manager = useChatManager()
  const {
    activePlugin: activePluginId,
    currentReferences,
    messagesLoading,
    threadsLoading,
    messages: loadedMessages,
    showTopicPicker,
    selectedThreadID,
    customCopilotId,
    customCopilots,
  } = state
  const thread = manager.getSelectedThread(state)
  const {textAreaRef} = useChat(inputRef)
  const isSharedThread = useIsSharedThread()
  const activePlugin = usePlugin(activePluginId)

  // if there's an entrypointMessage, then we're about to submit that and we shouldn't show the empty state
  const hasEntrypointMessage = useMemo(
    () => !state.selectedThreadID && copilotLocalStorage.getEntrypointMessage(),
    [state.selectedThreadID],
  )

  let messageContent = null
  let emptyContent = null

  let messages = loadedMessages
  if (copilotFeatureFlags.immersiveSubthreading) {
    messages = getActiveMessages(loadedMessages)
  }

  if (messages.length && messagesLoading.state === 'loaded') {
    messageContent = <Messages inputRef={textAreaRef} panelWidth={panelWidth} isMobile={isMobile} />
  } else if (
    (messagesLoading.state === 'loading' || messagesLoading.state === 'pending') &&
    state.selectedThreadID &&
    !showTopicPicker
  ) {
    messageContent = <ConversationLoader />
  } else if (
    messagesLoading.state === 'error' &&
    !!state.selectedThreadID &&
    (thread === null || messagesLoading.notFound)
  ) {
    emptyContent = isSharedThread ? <SharedThreadNotFound /> : <NotFoundError />
  } else if (messagesLoading.state === 'error' || threadsLoading.state === 'error') {
    emptyContent = <FailedToLoadThreadError />
  } else if (messagesLoading.state !== 'loading' && !hasEntrypointMessage) {
    if (customCopilotId || isCopilotSpacePath()) {
      emptyContent = isValidCopilotSpacePath(customCopilots, customCopilotId) ? (
        <ErrorBoundary fallback={<SpaceNotFound />}>
          <SpacesHomePageState selectedThreadID={selectedThreadID} textAreaRef={textAreaRef} onSubmit={onSubmit} />
        </ErrorBoundary>
      ) : (
        <SpaceNotFound />
      )
    } else if (activePlugin?.EmptyStateComponent) {
      const EmptyStateComponent = activePlugin.EmptyStateComponent
      emptyContent = <EmptyStateComponent chatState={state} />
    } else {
      emptyContent = <EmptyState showSuggestions={currentReferences.length === 0 && !state.currentTopic} />
    }
  }

  return (
    <ChatScrollContainer className={styles.container}>
      {emptyContent && <div className={styles.emptyContent}>{emptyContent}</div>}
      {messageContent && (
        <div className={styles.messageContent}>
          {messageContent}
          <ScrollToBottomButton />
          <MessagesPortalContainer />
        </div>
      )}

      <MenuPortalContainer />
    </ChatScrollContainer>
  )
}

const ScrollToBottomButton = () => {
  const {isScrolledUp, scrollToBottom} = useChatScroll()

  return (
    <IconButton
      aria-label="Scroll to bottom"
      className={clsx(styles.scrollToBottomButton, !isScrolledUp && styles.hidden)}
      onClick={() => scrollToBottom('smooth')}
      icon={ArrowDownIcon}
      tooltipDirection="n"
      // This button is not useful for keyboard or screen reader users because it will exist at the end of the
      // container, so the only way it can be focused is by tabbing through the whole container, by which point you
      // are already at the bottom. It would be confusing to already be at the bottom and then see a scroll button.
      tabIndex={-1}
      aria-hidden
    />
  )
}

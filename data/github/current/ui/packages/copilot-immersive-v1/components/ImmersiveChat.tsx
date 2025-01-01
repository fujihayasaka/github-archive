import {ChatMessagesGroup} from '@github-ui/copilot-chat/components/ChatMessagesGroup'
import {ChatScrollContainer, useChatScroll} from '@github-ui/copilot-chat/components/ChatScrollContainer'
import {MenuPortalContainer, MessagesPortalContainer} from '@github-ui/copilot-chat/components/PortalContainerUtils'
import {useChat} from '@github-ui/copilot-chat/hooks/use-chat'
import {useGroupedMessages} from '@github-ui/copilot-chat/hooks/use-grouped-messages'
import {threadName as getThreadName} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {getActiveMessages} from '@github-ui/copilot-chat/utils/copilot-chat-subthreading-helpers'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {getSelectedThread} from '@github-ui/copilot-chat/utils/get-selected-thread'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {ArrowDownIcon} from '@primer/octicons-react'
import {IconButton, Link} from '@primer/react'
import {clsx} from 'clsx'
import type React from 'react'

import {useIsSharedThread} from '../hooks/use-is-shared-thread'
import {ChatMessage} from './ChatMessage'
import {ConversationLoader} from './ConversationLoader'
import {ErrorState, SharedThreadForbidden} from './ErrorState'
import styles from './ImmersiveChat.module.css'

interface ImmersiveChatProps {
  inputRef?: React.RefObject<HTMLTextAreaElement>
  panelWidth?: number
  isMobile: boolean
  onSubmit?: (text: string) => Promise<void>
}

const Messages = ({inputRef, panelWidth, isMobile}: ImmersiveChatProps) => {
  const {scrollToBottom} = useChatScroll()
  const state = useChatState()
  const {streamingMessage, messages: completedMessages} = state

  const thread = getSelectedThread(state)
  const threadName = getThreadName(thread)
  const sharedMessageId = thread?.sharedMessageID

  const {messages, groupedMessages} = useGroupedMessages(state)
  const firstReplyId = messages.find(message => message.role === 'assistant')?.id

  // Instant scroll to bottom on mount
  useLayoutEffect(() => scrollToBottom('instant'), [scrollToBottom])

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
            // -1 indicates a streaming message; assign it to what it will become
            // otherwise, use the messageIndex, which will always be defined by this point
            const messageIndex = message.messageIndex === -1 ? completedMessages.length : message.messageIndex!

            return (
              <ChatMessage
                // Using `j` for the key goes against React's "best practice" of using unique keys,
                // but it's necessessary for accessibility. In order to keep keyboard focus on the action bar when
                // switching subthreads, we can't re-create it, which happens if React thinks it needs to re-create
                // the entire ChatMessage (rather than specific components within).
                //
                // Messages within a conversation cannot be reordered so the index should be safe to use.
                // eslint-disable-next-line @eslint-react/no-array-index-key
                key={j}
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

const AccessDeniedError = () => {
  return <ErrorState title="Access denied" description="You do not have permission to view this." />
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

export const ImmersiveChat = ({inputRef, panelWidth, isMobile}: ImmersiveChatProps) => {
  const state = useChatState()
  const {messagesLoading, threadsLoading, messages: loadedMessages, showTopicPicker} = state
  const thread = getSelectedThread(state)
  const {textAreaRef} = useChat(inputRef)
  const isSharedThread = useIsSharedThread()

  let messageContent = null
  let emptyContent = null

  const messages = getActiveMessages(loadedMessages)

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
    if (!copilotFeatureFlags.copilotSharedForbiddenError) {
      emptyContent = isSharedThread ? <SharedThreadNotFound /> : <NotFoundError />
    } else if (copilotFeatureFlags.copilotSharedForbiddenError) {
      if (isSharedThread && state.fetchSharedThreads?.ok === false) {
        emptyContent = state.fetchSharedThreads.status === 403 ? <SharedThreadForbidden /> : <SharedThreadNotFound />
      } else {
        emptyContent = <NotFoundError />
      }
    }
  } else if (messagesLoading.state === 'error' || threadsLoading.state === 'error') {
    emptyContent = threadsLoading.status === 403 ? <AccessDeniedError /> : <FailedToLoadThreadError />
  }

  return (
    <ChatScrollContainer className={styles.container}>
      <ScrollToBottomButton />
      {emptyContent && <div className={styles.emptyContent}>{emptyContent}</div>}
      {messageContent && (
        <div className={styles.messageContent}>
          {messageContent}
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
      as="a"
      aria-label="Scroll to bottom"
      className={clsx(styles.scrollToBottomButton, !isScrolledUp && styles.hidden)}
      onClick={() => scrollToBottom('smooth')}
      icon={ArrowDownIcon}
      tooltipDirection="n"
      href="#copilot-chat-textarea"
    />
  )
}

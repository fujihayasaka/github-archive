import {MenuPortalContainer, MessagesPortalContainer} from '@github-ui/copilot-chat/components/PortalContainerUtils'
import {useChat} from '@github-ui/copilot-chat/hooks/use-chat'
import {useMessages} from '@github-ui/copilot-chat/hooks/use-messages'
import {threadName as getThreadName} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import type {CopilotChatState} from '@github-ui/copilot-chat/utils/copilot-chat-reducer'
import type {CopilotChatMessage} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/utils/CopilotChatManagerContext'
import {isScrollable, scrollToBottomWithDelay, smoothScrollTo} from '@github-ui/copilot-chat/utils/scroll'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {ArrowDownIcon} from '@primer/octicons-react'
import {Link} from '@primer/react'
import {clsx} from 'clsx'
import type React from 'react'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'

import {ChatMessage} from './ChatMessage'
import {ConversationLoader} from './ConversationLoader'
import {EmptyState} from './EmptyState'
import {ErrorState} from './ErrorState'
import styles from './ImmersiveChat.module.css'

const Messages = ({
  messages,
  isWaitingOnCopilot,
  inputRef,
  onMessageReceived,
  panelWidth,
}: Pick<CopilotChatState, 'messages' | 'isWaitingOnCopilot'> & {
  inputRef: React.RefObject<HTMLTextAreaElement>
  onMessageReceived: ({forceScroll}: {forceScroll?: boolean}) => void
  panelWidth?: number
}) => {
  const state = useChatState()
  const {containerRef, setFocusZoneEnabled} = useMessages(isWaitingOnCopilot, messages, onMessageReceived)

  const manager = useChatManager()
  const threadName = getThreadName(manager.getSelectedThread(state))

  const copilotIsLoading = Boolean(state.streamingMessage) || state.isWaitingOnCopilot

  const nullMessage: CopilotChatMessage = {
    id: 'NULL_MESSAGE',
    role: 'assistant',
    content: '',
    createdAt: '',
    threadID: state.selectedThreadID || '',
    references: [],
  }

  return (
    <div ref={containerRef as React.RefObject<HTMLDivElement>}>
      <div className="sr-only">
        <h1>Copilot Chat</h1>
        <h2>{threadName}</h2>
      </div>
      {messages.map((message, i) => (
        <ChatMessage
          key={message.id}
          isLatestMessage={message.role === 'assistant' && i === messages.length - 1}
          message={message}
          inputRef={inputRef}
          panelWidth={panelWidth}
          setParentFocusZoneEnabled={setFocusZoneEnabled}
          isStreaming={false}
        />
      ))}
      {copilotIsLoading && (
        <ChatMessage
          message={state.streamingMessage ?? nullMessage}
          isStreaming
          isLatestMessage
          panelWidth={panelWidth}
        />
      )}
    </div>
  )
}

const FailedToLoadThreadError = () => (
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

const NotFoundError = () => (
  <ErrorState
    title="Conversation not found"
    description={
      <>
        This URL may be incorrect or the conversation may have been deleted.
        <br />
        Send a message to start a new conversation.
      </>
    }
  />
)

export const ImmersiveChat = ({
  inputRef,
  panelWidth,
}: {
  inputRef?: React.RefObject<HTMLTextAreaElement>
  panelWidth?: number
}) => {
  const state = useChatState()
  const manager = useChatManager()
  const {currentReferences, messagesLoading, threadsLoading, messages, showTopicPicker, scrollToTop} = state
  const thread = manager.getSelectedThread(state)
  const {textAreaRef} = useChat(inputRef)

  const messagesContainerRef = useRef<HTMLDivElement>(null)
  const scrollToTopRef = useRef(scrollToTop)
  const scrollOnLoadRef = useRef<boolean>(true)
  const [isUserScrolledUp, setIsUserScrolledUp] = useState(false)

  const isStreaming = useMemo(() => Boolean(state.streamingMessage), [state.streamingMessage])

  const handleScrollDownClick = useCallback(() => {
    messagesContainerRef.current?.scrollTo(0, messagesContainerRef.current.scrollHeight)
    setIsUserScrolledUp(false)
  }, [])

  const onMessageReceived = useCallback(
    ({forceScroll}: {forceScroll?: boolean}) => {
      if (!messagesContainerRef.current) return // This is not expected
      if (state.threadsLoading.state !== 'loaded') return // needed to prevent incorrect scroll height calculation

      if ((isUserScrolledUp && !forceScroll) || scrollToTopRef.current) return // The user has scrolled up, let's not scroll them back down

      const container = messagesContainerRef.current

      if (isScrollable(container)) {
        if (isStreaming || forceScroll) {
          setTimeout(() => {
            container.scrollTop = container.scrollHeight - container.clientHeight
          })
        } else {
          // to run once, on new thread load
          if (scrollOnLoadRef.current) {
            scrollToBottomWithDelay(container, 200) // scroll to bottom
            scrollOnLoadRef.current = false
          }
        }
      } else {
        smoothScrollTo(document.body, document.body.scrollHeight, 1000)
      }
    },
    [isStreaming, state.threadsLoading.state, isUserScrolledUp],
  )

  useLayoutEffect(() => {
    // Safari, because it is great, likes to randomly scroll up while we're streaming content in.
    // So every time we paint, we're going to slam the scroll position back to the bottom.
    const container = messagesContainerRef.current
    if (isStreaming && !isUserScrolledUp && container) {
      // eslint-disable-next-line @eslint-react/web-api/no-leaked-timeout
      setTimeout(() => {
        container.scrollTop = container.scrollHeight - container.clientHeight
      })
    }
  })

  // short-circuits the auto-scrolling if user scrolls up during active streaming
  useEffect(() => {
    const handleStreamingScroll = () => {
      if (messagesContainerRef.current) {
        const {scrollTop, scrollHeight, clientHeight} = messagesContainerRef.current
        setIsUserScrolledUp(scrollTop + clientHeight < scrollHeight - 75)
      }
    }

    const container = messagesContainerRef.current as HTMLElement
    if (state.threadsLoading.state && container) {
      // eslint-disable-next-line github/prefer-observers
      container.addEventListener('scroll', handleStreamingScroll)
    } else {
      container.removeEventListener('scroll', handleStreamingScroll)
    }

    return () => {
      if (container) {
        container.removeEventListener('scroll', handleStreamingScroll)
      }
    }
  }, [state.threadsLoading.state])

  let messageContent = null
  let emptyContent = null

  if (messages.length) {
    messageContent = (
      <Messages {...state} inputRef={textAreaRef} onMessageReceived={onMessageReceived} panelWidth={panelWidth} />
    )
  } else if (messagesLoading.state === 'loading' && state.selectedThreadID && !showTopicPicker) {
    messageContent = <ConversationLoader />
  } else if (messagesLoading.state === 'error' && !!state.selectedThreadID && thread === null) {
    emptyContent = <NotFoundError />
  } else if (messagesLoading.state === 'error' || threadsLoading.state === 'error') {
    emptyContent = <FailedToLoadThreadError />
  } else if (messagesLoading.state !== 'loading') {
    emptyContent = <EmptyState showSuggestions={currentReferences.length === 0 && !state.currentTopic} />
  }

  return (
    <div ref={messagesContainerRef} className={clsx(styles.container, messageContent && styles.withMessages)}>
      {emptyContent}
      {messageContent && (
        <>
          <div className={styles.content}>
            {messageContent}
            <MessagesPortalContainer />
            {isUserScrolledUp && (
              <button
                className={styles.scrollToBottomButton}
                onClick={handleScrollDownClick}
                aria-label="Scroll to bottom"
              >
                <ArrowDownIcon />
              </button>
            )}
          </div>
        </>
      )}

      <MenuPortalContainer />
    </div>
  )
}

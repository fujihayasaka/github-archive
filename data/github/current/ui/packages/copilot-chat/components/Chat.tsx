import {sendEvent} from '@github-ui/hydro-analytics'
import {AlertIcon} from '@primer/octicons-react'
import {Box, Button, Heading, Spinner, Text} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import type React from 'react'
import {type UIEvent, useCallback, useEffect, useMemo, useRef, useState} from 'react'

import {useChat} from '../hooks/use-chat'
import {useMessages} from '../hooks/use-messages'
import {suggestedPrompts} from '../utils/constants'
import {COPILOT_PATH, shuffle} from '../utils/copilot-chat-helpers'
import type {CopilotChatState} from '../utils/copilot-chat-reducer'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {isScrollable} from '../utils/scroll'
import {ChatInput} from './ChatInput'
import {ChatMessage} from './ChatMessage'
import CopilotSuggestions from './CopilotSuggestions'
import {CurrentChatReferences} from './CurrentChatReferences'
import {MenuPortalContainer, MessagesPortalContainer} from './PortalContainerUtils'
import TopicIndexedMessage from './TopicIndexedMessage'
import {TopicIndicator} from './TopicIndicator'
import {TopicPicker} from './TopicPicker'

interface Suggestion {
  heading: string
  content: string
}

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
  const {showTopicPicker} = state
  const isImmersiveV1 = copilotFeatureFlags.copilotImmersiveV1 && state.mode === 'immersive'
  const {containerRef, setFocusZoneEnabled} = useMessages(isWaitingOnCopilot, messages, onMessageReceived)

  return (
    <>
      <h2 className="sr-only">Copilot Chat</h2>
      {!showTopicPicker ? (
        <Box
          ref={containerRef as React.RefObject<HTMLDivElement>}
          sx={{
            display: 'flex',
            flexDirection: 'column',
            minHeight: '0',
            flexGrow: 1,
          }}
        >
          <Box className="copilot-messages-container" sx={{display: 'flex', flexDirection: 'column', flexGrow: 1}}>
            {!isImmersiveV1 && <TopicIndexedMessage />}
            {messages.map((message, i) => (
              <ChatMessage
                // eslint-disable-next-line @eslint-react/no-array-index-key
                key={i}
                isLatestMessage={message.role === 'assistant' && i === messages.length - 1}
                message={message}
                inputRef={inputRef}
                panelWidth={panelWidth}
                setParentFocusZoneEnabled={setFocusZoneEnabled}
              />
            ))}

            {state.streamingMessage && (
              <ChatMessage message={state.streamingMessage} isStreaming isLatestMessage panelWidth={panelWidth} />
            )}
          </Box>
          {!showTopicPicker && state.currentReferences.length > 0 && <CurrentChatReferences />}
        </Box>
      ) : (
        <TopicPicker />
      )}
    </>
  )
}

const Loading = () => {
  return (
    <Box sx={{m: 'auto', display: 'flex', flexDirection: 'column', alignItems: 'center'}}>
      <Spinner size="large" />
      <Box
        sx={{
          p: 3,
          color: 'fg.subtle',
        }}
      >
        Loading conversation…
      </Box>
    </Box>
  )
}

const Error = () => {
  const {mode, reviewLab} = useChatState()
  return (
    <Box
      sx={{
        display: 'flex',
        gap: '2',
        alignItems: 'center',
        py: 3,
        pr: 3,
        pl: mode === 'immersive' ? 3 : 2,
        color: 'fg.subtle',
      }}
    >
      <Octicon icon={AlertIcon} />
      Failed to load previous messages.
      {reviewLab && <>&nbsp;You are in a review lab. Please check that you are connected to the Developer VPN.</>}
    </Box>
  )
}

export const Chat = ({
  inputRef,
  panelWidth,
}: {
  inputRef?: React.RefObject<HTMLTextAreaElement>
  panelWidth?: number
}) => {
  const state = useChatState()
  const manager = useChatManager()
  const {
    currentReferences,
    messagesLoading,
    messagesRestored,
    threadsLoading,
    currentTopic,
    messages,
    mode,
    selectedThreadID,
    showTopicPicker,
    context,
    scrollToTop,
  } = state
  const thread = manager.getSelectedThread(state)
  const suggestions = useMemo(() => getSuggestions(), [])
  const {textAreaRef} = useChat(inputRef)

  const messagesContainerRef = useRef<HTMLDivElement>(null)
  const scrolledToBottomRef = useRef(true)
  const scrollToTopRef = useRef(scrollToTop)

  useEffect(() => {
    if (!selectedThreadID || mode === 'assistive') return

    const threadPath = `${COPILOT_PATH}/c/${selectedThreadID}`
    if (window.location.pathname === threadPath || messages.length === 0) return

    history.pushState(null, '', threadPath)
  }, [selectedThreadID, mode, messages.length])

  const handleUserSubmit = useCallback(
    async (content: string) => {
      scrollToTopRef.current = false
      const trimmedContent = content.trim()
      if (trimmedContent === '') return

      await manager.sendChatMessage(
        thread,
        content,
        currentReferences,
        currentTopic,
        context,
        undefined,
        state.customInstructions,
        undefined,
      )
    },
    [context, currentReferences, currentTopic, manager, state.customInstructions, thread],
  )

  const handleScroll = useCallback((e: UIEvent<HTMLDivElement>) => {
    const element = e.target as HTMLElement
    // This calculation can be finnicky with fractional pixels. If we're within 1px of the bottom, we are close enough.
    scrolledToBottomRef.current = Math.abs(element.scrollHeight - element.scrollTop - element.clientHeight) < 1
  }, [])

  const onMessageReceived = useCallback(({forceScroll}: {forceScroll?: boolean}) => {
    if (!messagesContainerRef.current) return // This is not expected
    if ((!scrolledToBottomRef.current && !forceScroll) || scrollToTopRef.current) return // The user has scrolled up, let's not scroll them back down

    // Depending on the screen size and the mode, we might either have a scroll
    // container around the messages, or we might use the window scroll.
    if (isScrollable(messagesContainerRef.current)) {
      messagesContainerRef.current.scrollTo(0, messagesContainerRef.current.scrollHeight)
    } else {
      window.scrollTo(0, document.body.scrollHeight)
    }
  }, [])

  const hasRestoredMessages = messagesRestored && messages.length > 0
  const isLoading =
    messagesLoading.state === 'loading' &&
    state.selectedThreadID &&
    !showTopicPicker &&
    // don't show the loading state if we have placeholder messages to show
    !hasRestoredMessages
  const isError = messagesLoading.state === 'error' || threadsLoading.state === 'error'
  const isLoaded = messagesLoading.state === 'loaded' || hasRestoredMessages
  const shouldShowChatInput = !showTopicPicker
  const isImmersiveV1 = copilotFeatureFlags.copilotImmersiveV1 && state.mode === 'immersive'
  // We store this at the first render and don't change it because we don't want the suggested prompts to suddenly pop up
  // when the popover is dismissed. Instead we'll show prompts on subsequent loads if the popover is dismissed.
  const [renderedPopoverOnFirstLoad] = useState(state.renderAttachKnowledgeBaseHerePopover)
  // If there is a popover or a reference attached then we shouldn't show the suggested prompts
  const shouldShowSuggestedPrompts = Boolean(
    !isLoading &&
      !state.currentTopic &&
      !showTopicPicker &&
      messages.length === 0 &&
      !renderedPopoverOnFirstLoad &&
      currentReferences.length === 0,
  )

  return (
    <>
      <Box
        className="copilot-chat-messages"
        onScroll={handleScroll}
        ref={messagesContainerRef}
        sx={{
          overflowY: 'auto',
          overscrollBehavior: 'contain',
          display: 'flex',
          flexDirection: 'column',
          flex: '1 1 auto',
          scrollbarGutter: 'stable',
        }}
      >
        {isLoading && <Loading />}
        {isError && <Error />}
        {isLoaded && !isLoading && (
          <Messages {...state} inputRef={textAreaRef} onMessageReceived={onMessageReceived} panelWidth={panelWidth} />
        )}
        <MessagesPortalContainer />
      </Box>
      {shouldShowSuggestedPrompts && (
        <Box
          className="copilot-chat-messages"
          sx={{
            display: 'grid',
            gridTemplateColumns: '1fr 1fr',
            gap: 2,
            px: 3,
            mb: 3,
            scrollbarGutter: 'stable',
          }}
        >
          {suggestions.map((s, i) => (
            <SuggestedPrompt
              // eslint-disable-next-line @eslint-react/no-array-index-key
              key={i}
              heading={s.heading}
              content={s.content}
              onSubmit={() => {
                void manager.sendChatMessage(
                  manager.getSelectedThread(state),
                  s.content,
                  state.currentReferences,
                  state.currentTopic,
                  state.context,
                )
                sendEvent('copilot_chat_suggestion_click', {
                  topic: state.currentTopic?.name,
                })
              }}
            />
          ))}
        </Box>
      )}
      {!isLoading && shouldShowChatInput && (
        <Box
          className="copilot-chat-input copilot-chat-input-outer"
          sx={{
            display: 'flex',
            flexDirection: 'column',
            mt: 'auto',
            px: 3,
            pb: 3,
            // So messages don't overlap the outline when input is focussed
            zIndex: 1,
          }}
        >
          {!shouldShowSuggestedPrompts && messages.length === 0 && !state.showTopicPicker && (
            <CopilotSuggestions panelWidth={panelWidth} suggestionKind="initial" />
          )}
          <div>
            {copilotFeatureFlags.repoCustomInstructions ? <TopicIndicator /> : null}
            <ChatInput
              textAreaRef={textAreaRef}
              onSubmit={handleUserSubmit}
              isLoading={state.isWaitingOnCopilot || state.slashCommandLoading.state === 'loading'}
              isStreaming={!!state.streamingMessage}
              panelWidth={panelWidth}
            />
          </div>
          {isImmersiveV1 && (
            <Box
              sx={{
                textAlign: 'center',
                mt: 2,
                color: 'fg.subtle',
                fontSize: '12px',
              }}
            >
              Copilot can make mistakes. Review output before use.
            </Box>
          )}
        </Box>
      )}
      <MenuPortalContainer />
    </>
  )
}

function SuggestedPrompt({heading, content, onSubmit}: {heading: string; content: string; onSubmit: () => void}) {
  return (
    <Button
      sx={{
        bg: 'canvas.default',
        height: 'auto',
        minWidth: 'auto',
        borderBottom: '1px solid',
        borderColor: 'border.default',
        border: '1px solid var(--borderColor-default, var(--color-border-default))',
        flex: '1 1 49%',
        display: 'flex',
        flexDirection: 'column',
        justifyContent: 'center',
        p: 2,
      }}
      onClick={onSubmit}
    >
      <Heading
        as="h3"
        sx={{
          textAlign: 'center',
          fontSize: 1,
          m: 0,
          mb: 1,
          wordWrap: 'break-word',
          overflowWrap: 'break-word',
          whiteSpace: 'normal',
        }}
      >
        {heading}
      </Heading>
      {/* @ts-expect-error - TS doesn't like text-wrap yet */}
      <Text
        as="p"
        sx={{
          fontSize: 0,
          fontWeight: 400,
          textAlign: 'center',
          color: 'fg.muted',
          m: 0,
          textWrap: 'balance',
          wordWrap: 'break-word',
          overflowWrap: 'break-word',
          whiteSpace: 'normal',
        }}
      >
        {content}
      </Text>
    </Button>
  )
}

function getSuggestions(): Suggestion[] {
  const categories = shuffle(Object.keys(suggestedPrompts)).slice(0, 4)
  return categories.map(c => ({
    heading: c,
    content: shuffle(suggestedPrompts[c]!)[0]!,
  }))
}

import {sendEvent} from '@github-ui/hydro-analytics'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {AlertIcon} from '@primer/octicons-react'
import {Box, Button, Heading, Spinner, Text} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import type React from 'react'
import {useCallback, useEffect, useMemo, useState} from 'react'

import {useChat} from '../hooks/use-chat'
import {COPILOT_PATH, shuffle} from '../utils/copilot-chat-helpers'
import type {CopilotChatState} from '../utils/copilot-chat-reducer'
import {getActiveMessages} from '../utils/copilot-chat-subthreading-helpers'
import type {CopilotChatMessage} from '../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {suggestedPrompts} from '../utils/prompts'
import {AmbientErrorBanner} from './AmbientErrorBanner'
import styles from './Chat.module.css'
import {ChatInput} from './ChatInput'
import {ChatMessage} from './ChatMessage'
import {ChatMessagesGroup, groupChatMessages} from './ChatMessagesGroup'
import {ChatScrollContainer, useChatScroll} from './ChatScrollContainer'
import {Confirmation} from './Confirmation'
import CopilotSuggestions from './CopilotSuggestions'
import {LegalDisclaimer} from './LegalDisclaimer'
import {MenuPortalContainer, MessagesPortalContainer} from './PortalContainerUtils'
import {useEntitlement} from './quota/EntitlementContext'
import {QuotaExceededBanner} from './quota/QuotaExceededBanner'
import {QuotaExceededEmptyState} from './quota/QuotaExceededEmptyState'
import {QuotaMeterBanner} from './quota/QuotaMeterBanner'
import TopicIndexedMessage from './TopicIndexedMessage'
import {TopicIndicator} from './TopicIndicator'
import {TopicPicker} from './TopicPicker'

interface Suggestion {
  heading: string
  content: string
}

const Messages = ({
  messages,
  inputRef,
  showQuotaExceededEmptyState,
}: Pick<CopilotChatState, 'messages' | 'isWaitingOnCopilot'> & {
  inputRef: React.RefObject<HTMLTextAreaElement>
  showQuotaExceededEmptyState: boolean
}) => {
  const state = useChatState()
  const {showTopicPicker, streamingMessage} = state
  const isImmersive = state.mode === 'immersive'
  const {scrollToBottom} = useChatScroll()

  let activeMessages = messages
  if (copilotFeatureFlags.immersiveSubthreading) {
    activeMessages = getActiveMessages(messages)
  }

  if (state.streamingMessage) activeMessages.push(state.streamingMessage)

  // Instant scroll to bottom on mount
  useLayoutEffect(() => scrollToBottom('instant'), [scrollToBottom])

  const groupedMessages = groupChatMessages(activeMessages)

  return (
    <>
      <h2 className="sr-only">Copilot Chat</h2>
      {showQuotaExceededEmptyState ? (
        <QuotaExceededEmptyState />
      ) : showTopicPicker ? (
        <TopicPicker />
      ) : (
        <Box
          sx={{
            display: 'flex',
            flexDirection: 'column',
            minHeight: '0',
            flexGrow: 1,
          }}
        >
          <Box className="copilot-messages-container" sx={{display: 'flex', flexDirection: 'column', flexGrow: 1}}>
            {activeMessages.length === 0 && (
              <p className={styles.legalText}>
                <LegalDisclaimer />
              </p>
            )}
            {!isImmersive && !copilotFeatureFlags.topicsAsReferences && <TopicIndexedMessage />}
            {groupedMessages.map((group, i) => (
              // eslint-disable-next-line @eslint-react/no-array-index-key
              <ChatMessagesGroup key={i} isLastGroup={i === groupedMessages.length - 1}>
                {group.map((message, j) => {
                  const isLastMessage = i === groupedMessages.length - 1 && j === group.length - 1
                  return (
                    (!isMessageEmpty(message) ||
                      !copilotFeatureFlags.dotcomChatClientSideSkills ||
                      message.error?.type === 'agentUnauthorized' ||
                      shouldShowClientSkillMessage(message, activeMessages, isLastMessage, state)) && (
                      <ChatMessage
                        // eslint-disable-next-line @eslint-react/no-array-index-key
                        key={j}
                        isLatestMessage={isLastMessage}
                        isFirstReply={activeMessages.length === 1}
                        isStreaming={message.id === streamingMessage?.id}
                        message={message}
                        inputRef={inputRef}
                      />
                    )
                  )
                })}
              </ChatMessagesGroup>
            ))}
            {state.clientSkillConfirmation && copilotFeatureFlags.dotcomChatClientSideSkills && (
              <div className="m-3">
                <Confirmation
                  confirmation={state.clientSkillConfirmation}
                  handleConfirmation={clientConfirmation =>
                    state.clientSkillConfirmation?.onSubmit?.(clientConfirmation.state === 'accepted')
                  }
                  isLatestMessage
                />
              </div>
            )}
          </Box>
        </Box>
      )}
    </>
  )
}

const isMessageEmpty = (message: CopilotChatMessage) => {
  return (
    !message.content &&
    (!message.confirmations || message.confirmations.length === 0) &&
    (!message.clientConfirmations || message.clientConfirmations.length === 0)
  )
}

const isClientSkillMessage = (message: CopilotChatMessage) => {
  return (
    (message.clientSkillsRequests && message.clientSkillsRequests.length > 0) ||
    (message.clientToolResults && message.clientToolResults.length > 0)
  )
}

const shouldShowClientSkillMessage = (
  message: CopilotChatMessage,
  activeMessages: CopilotChatMessage[],
  isLastMessage: boolean,
  state: CopilotChatState,
) => {
  return isClientSkillMessage(message) && isLastMessage && !state.streamingMessage && !state.clientSkillConfirmation
}

const Loading = () => {
  return (
    <Box
      sx={{
        m: 'auto',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        height: '100%',
        justifyContent: 'center',
      }}
    >
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

export const Chat = ({inputRef}: {inputRef?: React.RefObject<HTMLTextAreaElement>}) => {
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
  } = state
  const thread = manager.getSelectedThread(state)
  const suggestions = useMemo(() => getSuggestions(), [])
  const {textAreaRef} = useChat(inputRef)
  const {chatQuotaExceeded, isLicensedLimited, reloadQuota} = useEntitlement()
  const {ambientError} = useChatState()
  const showAmbientErrorBanner = copilotFeatureFlags.ambientErrorBanner && ambientError

  useEffect(() => {
    if (!selectedThreadID || mode === 'assistive') return

    const threadPath = `${COPILOT_PATH}/c/${selectedThreadID}`
    if (window.location.pathname === threadPath || messages.length === 0) return

    history.pushState(null, '', threadPath)
  }, [selectedThreadID, mode, messages.length])

  const handleUserSubmit = useCallback(
    async (content: string) => {
      const trimmedContent = content.trim()
      if (trimmedContent === '') return

      reloadQuota()

      await manager.sendChatMessage({
        thread,
        content,
        references: currentReferences,
        topic: currentTopic,
        context,
        customInstructions: state.customInstructions,
      })
    },
    [context, currentReferences, currentTopic, manager, reloadQuota, state.customInstructions, thread],
  )

  const hasRestoredMessages = messagesRestored && messages.length > 0
  const isLoading =
    messagesLoading.state === 'loading' &&
    state.selectedThreadID &&
    !showTopicPicker &&
    // don't show the loading state if we have placeholder messages to show
    !hasRestoredMessages
  const isError = messagesLoading.state === 'error' || threadsLoading.state === 'error'
  const isLoaded = messagesLoading.state === 'loaded' || hasRestoredMessages
  const showQuotaExceededEmptyState = chatQuotaExceeded && (showTopicPicker || !thread)
  const shouldShowChatInput = !showTopicPicker && !showQuotaExceededEmptyState
  // We store this at the first render and don't change it because we don't want the suggested prompts to suddenly pop up
  // when the popover is dismissed. Instead we'll show prompts on subsequent loads if the popover is dismissed.
  const [renderedPopoverOnFirstLoad] = useState(state.renderAttachKnowledgeBaseHerePopover)

  let activeMessages = messages
  if (copilotFeatureFlags.immersiveSubthreading) {
    activeMessages = getActiveMessages(messages)
  }
  // If there is a popover or a reference attached then we shouldn't show the suggested prompts
  const shouldShowSuggestedPrompts = Boolean(
    !isLoading &&
      !state.currentTopic &&
      !showTopicPicker &&
      activeMessages.length === 0 &&
      !renderedPopoverOnFirstLoad &&
      currentReferences.length === 0,
  )

  return (
    <>
      <ChatScrollContainer
        className="copilot-chat-messages"
        style={{
          flex: '1 1 auto',
        }}
      >
        {isLoading && <Loading />}
        {isError && <Error />}
        {isLoaded && !isLoading && (
          <Messages {...state} inputRef={textAreaRef} showQuotaExceededEmptyState={showQuotaExceededEmptyState} />
        )}
        <MessagesPortalContainer />
      </ChatScrollContainer>
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
                void manager.sendChatMessage({
                  thread: manager.getSelectedThread(state),
                  content: s.content,
                  references: state.currentReferences,
                  topic: state.currentTopic,
                  context: state.context,
                })
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
          {chatQuotaExceeded ? (
            <QuotaExceededBanner />
          ) : (
            <>
              {!shouldShowSuggestedPrompts && activeMessages.length === 0 && !state.showTopicPicker && (
                <CopilotSuggestions suggestionKind="initial" />
              )}
              <div>
                {isLicensedLimited && <QuotaMeterBanner />}
                {showAmbientErrorBanner && <AmbientErrorBanner ambientError={ambientError} />}
                {!copilotFeatureFlags.topicsAsReferences && <TopicIndicator />}
                <ChatInput
                  key={selectedThreadID}
                  textAreaRef={textAreaRef}
                  onSubmit={handleUserSubmit}
                  isStreaming={!!state.streamingMessage}
                  size="small"
                />
              </div>
            </>
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

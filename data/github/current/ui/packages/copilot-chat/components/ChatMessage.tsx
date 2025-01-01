import {MarkdownRenderer} from '@github-ui/copilot-markdown'
import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {sendEvent} from '@github-ui/hydro-analytics'
import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {testIdProps} from '@github-ui/test-id-props'
import {CheckIcon} from '@primer/octicons-react'
import {Box, Text} from '@primer/react'
import {clsx} from 'clsx'
import type React from 'react'
import {useCallback} from 'react'

import {useChatMessageBehavior} from '../hooks/use-chat-message-behavior'
import {filterUniqueConfirmations, isAgent} from '../utils/copilot-chat-helpers'
import type {CopilotCodeSearchConfirmation, SnippetReference} from '../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {ChatImage} from './ChatImage'
import styles from './ChatMessage.module.css'
import {type ChatMessageContextProps, ChatMessageProvider, useChatMessage} from './ChatMessageContext'
import {
  ChatMessageReferencesList,
  ChatMessageReferenceTokens,
  chatMessageRenderableReferenceTypes,
} from './ChatReferences'
import {Confirmation} from './Confirmation'
import {CopilotBadge} from './CopilotBadgeV2'
import {AgentErrors, ErrorMessage} from './Errors'
import {Feedback} from './Feedback'
import {messageFromFunctionCall} from './FunctionLoadingUtils'
import {InterruptedBanner} from './InterruptedBanner'
import {RetryButton} from './RetryButton'
import {UserMessage} from './UserMessage'
import {WithShimmerEffect} from './WithShimmerEffect'

export interface ChatMessageProps extends ChatMessageContextProps, InnerChatMessageProps {}

type InnerChatMessageProps = {
  isLatestMessage?: boolean
  isFirstReply?: boolean
  inputRef?: React.RefObject<HTMLInputElement> | React.RefObject<HTMLTextAreaElement>
  isLoading?: boolean
  isStreaming?: boolean
  excludeFeedback?: boolean
}

const InnerChatMessage = ({isLatestMessage, isFirstReply, isStreaming, ...props}: InnerChatMessageProps) => {
  const {message} = useChatMessage()
  const state = useChatState()
  const manager = useChatManager()

  const {
    author,
    handleConfirmationAction,
    handleRetryErrorMessage,
    hasClientConfirmations,
    isAI,
    isCopilot,
    isError,
    isAgentError,
    isInterrupted,
    isLoading: isLoadingContent,
    isUser: isFromUser,
    myRef,
    onFeedbackSubmitted,
    renderContentArea,
    rendererConfig,
    renderFeedback,
    shouldShowMessageActions,
    skillExecutionToUseForRespondingText,
    showRetryButton,
  } = useChatMessageBehavior({
    excludeFeedback: props.excludeFeedback,
    inputRef: props.inputRef,
    isLatestMessage,
    isLoading: props.isLoading,
    isStreaming,
    excludeReferencesFromFocusZone: true,
  })
  const hasClientToolResults = message.clientToolResults && message.clientToolResults.length > 0
  const hasClientSkillsRequests = message.clientSkillsRequests && message.clientSkillsRequests.length > 0
  const isUser = isFromUser && !hasClientToolResults
  const isCopilotLoading = isLoadingContent || hasClientToolResults || hasClientSkillsRequests
  const isLoading = isCopilotLoading && isLatestMessage
  const isCopilotMessage = isCopilot || hasClientToolResults
  const renderableReferences = message.references?.filter(ref => chatMessageRenderableReferenceTypes().has(ref.type))
  const maxMessagesReached = manager.maxMessagesReached()

  const image = message.mediaContent?.find(media => media.mediaType.startsWith('image/'))
  const shouldShowImages = (copilotFeatureFlags.attachImagesImmersive && typeof image !== 'undefined') || false

  const onLinkClick = useCallback(
    (event: MouseEvent) => {
      const target = event.target as HTMLAnchorElement
      const href = target.href
      const reference = message.references?.find(r => (r as SnippetReference).url === href)
      if (reference && state.mode === 'immersive') {
        manager.selectReference(reference)
        event.preventDefault()
      }
    },
    [manager, message.references, state.mode],
  )

  return (
    <div
      className={clsx('message-container', styles.messageContainer, isUser && styles.user, isAI && styles.ai)}
      ref={myRef}
      {...testIdProps(`message-${isError ? 'error' : isStreaming ? 'streaming' : message.id}`)}
    >
      {isUser && shouldShowImages && <ChatImage src={image?.url || ''} alt="Uploaded image" />}
      {isCopilotMessage || hasClientToolResults ? (
        <CopilotBadge
          isLoading={isCopilotLoading && isLatestMessage}
          isError={isError && message.error?.type !== 'agentUnauthorized'}
          mode={state.mode}
          isFirstMessage={isFirstReply}
          isLoadingSkills={
            (message.skillExecutions ?? []).length > 0 && isCopilotLoading && message.content === '' && isLatestMessage
          }
          message={message.content || ''}
          createdAt={message.createdAt}
        />
      ) : isAI ? (
        <div className={styles.avatar}>
          <GitHubAvatar
            src={author.avatarURL}
            size={24}
            aria-label={`${author.name} avatar`}
            alt={`${author.name} avatar`}
            data-testid="chat-message-author-avatar"
          />
        </div>
      ) : null}

      {isUser && (
        <ChatMessageReferenceTokens size="small" align="right" className="mb-2" references={message.references ?? []} />
      )}

      <div className={clsx(styles.message, isUser && styles.user)}>
        {hasClientConfirmations && message.clientConfirmations?.length ? (
          <Box
            className="my-1"
            sx={{
              display: 'flex',
              alignItems: 'baseline',
              justifyContent: isUser ? 'flex-end' : '',
            }}
            data-testid="chat-message-client-confirmations"
          >
            <Text sx={{fontWeight: 'normal', color: 'var(--fgColor-muted)'}}>
              <CheckIcon /> {author.name} {message.clientConfirmations?.[0]?.state} the action
            </Text>
          </Box>
        ) : null}
        {isCopilot && isLoading && skillExecutionToUseForRespondingText && (
          <WithShimmerEffect className={clsx(styles.skillExecutionText, 'mb-2 mt-1 ml-2')}>
            {`${messageFromFunctionCall(skillExecutionToUseForRespondingText)}...`}
          </WithShimmerEffect>
        )}
        <div className={clsx(styles.messageContent, !!hasClientConfirmations && styles.hasClientConfirmations)}>
          {isCopilotMessage && isLatestMessage && !renderContentArea ? (
            <span className={styles.blinkingCursor}>&#9611;</span>
          ) : null}
          {renderContentArea && (
            <>
              <Box
                className="js-snippet-clipboard-copy-unpositioned"
                sx={{
                  fontSize: 1,
                  px: 2,
                  py: 1,
                  zIndex: 1,
                  '.snippet-clipboard-content': {
                    position: 'relative',
                    overflow: 'auto',
                    display: 'flex',
                    justifyContent: 'space-between',
                    backgroundColor: 'canvas.subtle',
                    marginBottom: 3,
                    zIndex: 1,
                    pre: {
                      marginBottom: 0,
                    },

                    'clipboard-copy': {
                      width: '28px',
                      height: '28px',
                    },
                  },
                }}
              >
                {message.role === 'assistant' &&
                  (renderableReferences?.length ? (
                    <ChatMessageReferencesList className="mb-3" references={message.references ?? []} />
                  ) : null)}

                {isCopilot && props.isLoading ? (
                  <>
                    <LoadingSkeleton variant="rounded" height="12px" width="random" />
                    <LoadingSkeleton variant="rounded" height="12px" width="random" />
                    <LoadingSkeleton variant="rounded" height="12px" width="random" />
                  </>
                ) : (
                  !hasClientConfirmations &&
                  (isUser ? (
                    <UserMessage>{message.content ?? ''}</UserMessage>
                  ) : (
                    <MarkdownRenderer
                      markdown={message.content ?? ''}
                      onLinkClick={onLinkClick}
                      chatMode="assistive"
                      {...rendererConfig}
                    />
                  ))
                )}
                {isError ? <ErrorMessage manager={manager} /> : null}
                {isAgentError && message.agentErrors?.length ? <AgentErrors errors={message.agentErrors} /> : null}
                {isInterrupted ? (
                  <InterruptedBanner messageHasContent={!!message.content || !!message.skillExecutions?.length} />
                ) : null}
                {(isCopilot || isAgent(author)) &&
                  filterUniqueConfirmations(message.confirmations).map((confirmation, i) => {
                    return (confirmation.confirmation as CopilotCodeSearchConfirmation).name === 'indexrepo' ? null : (
                      <Confirmation
                        confirmation={confirmation}
                        handleConfirmation={handleConfirmationAction}
                        // eslint-disable-next-line @eslint-react/no-array-index-key
                        key={i}
                        isLatestMessage={isLatestMessage}
                      />
                    )
                  })}
              </Box>
              {!shouldShowMessageActions && showRetryButton && (
                <RetryButton handleRetryMessage={handleRetryErrorMessage} disabled={maxMessagesReached} />
              )}
              {shouldShowMessageActions && (
                <Box
                  className="message-actions"
                  data-testid="message-action-bar"
                  sx={{
                    display: 'inline-flex',
                    alignItems: 'center',
                    // Floating actions for previous messages
                    position: isLatestMessage ? undefined : 'absolute',
                    bottom: isLatestMessage ? undefined : '-2.25rem',
                    borderRadius: isLatestMessage ? undefined : 2,
                    boxShadow: isLatestMessage ? undefined : 'var(--shadow-floating-small)',
                    // Opacity and pointer events rules instead of changing `display` let us animate the actions in and out
                    opacity: isLatestMessage ? undefined : 0,
                    pointerEvents: isLatestMessage ? undefined : 'none',

                    // Adds a lil invisible target to make hovering less precise so they don’t disappear if you miss a bit
                    '&::before': {
                      // Not on the inline actions though
                      content: isLatestMessage ? undefined : '""',
                      // Make it wider than it is tall to cover the triangular hover path
                      inset: '-0.5rem -0.75rem',
                      zIndex: -1,
                      position: 'absolute',
                    },
                  }}
                >
                  {renderFeedback && (
                    <Feedback iconSize="small" returnFocusRef={myRef} onFeedbackSubmitted={onFeedbackSubmitted} />
                  )}
                  {isCopilot && !!message.content && !isStreaming && (
                    <CopyToClipboardButton
                      textToCopy={message.content ?? ''}
                      ariaLabel="Copy to clipboard"
                      size="small"
                      className="d-flex flex-items-center"
                      onCopy={() => {
                        sendEvent('copilot_chat.activate', {
                          target: 'CHAT_MESSAGE_COPY',
                          mode: state.mode,
                        })
                      }}
                    />
                  )}
                  {showRetryButton && (
                    <RetryButton handleRetryMessage={handleRetryErrorMessage} disabled={maxMessagesReached} />
                  )}
                </Box>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  )
}

export const ChatMessage = ({message, ...props}: ChatMessageProps) => (
  <ChatMessageProvider message={message}>
    <InnerChatMessage {...props} />
  </ChatMessageProvider>
)

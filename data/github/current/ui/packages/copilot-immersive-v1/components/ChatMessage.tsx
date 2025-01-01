import {announce, announceFromElement} from '@github-ui/aria-live'
import {
  type ChatMessageContextProps,
  ChatMessageProvider,
  useChatMessage,
} from '@github-ui/copilot-chat/components/ChatMessageContext'
import {Confirmation} from '@github-ui/copilot-chat/components/Confirmation'
import {Feedback} from '@github-ui/copilot-chat/components/Feedback'
import {FunctionCallBadge} from '@github-ui/copilot-chat/components/FunctionCallBadge'
import {
  buildMessage,
  filterUniqueConfirmations,
  findAuthor,
  isAgent,
} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import type {CopilotChatManager} from '@github-ui/copilot-chat/utils/copilot-chat-manager'
import type {
  AgentUnauthorizedChatError,
  CopilotAgentError,
  CopilotClientConfirmation,
  CopilotCodeSearchConfirmation,
} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/utils/CopilotChatManagerContext'
import {MarkdownRenderer} from '@github-ui/copilot-markdown'
import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {sendEvent} from '@github-ui/hydro-analytics'
import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {AlertFillIcon, LinkIcon, MarkGithubIcon, XIcon} from '@primer/octicons-react'
import {Button, Flash, IconButton, Stack, useFocusZone} from '@primer/react'
import {clsx} from 'clsx'
import type React from 'react'
import {memo, useCallback, useEffect, useRef, useState} from 'react'

import styles from './ChatMessage.module.css'
import {ChatMessageReferences} from './ChatMessageReferences'
import CopilotBadge from './CopilotBadge'
import {MarkdownViewer} from './MarkdownViewer/MarkdownViewer'

export interface ChatMessageProps extends ChatMessageContextProps, InnerChatMessageProps {}

type InnerChatMessageProps = {
  isLatestMessage?: boolean
  inputRef?: React.RefObject<HTMLInputElement> | React.RefObject<HTMLTextAreaElement>
  isLoading?: boolean
  isStreaming?: boolean
  excludeFeedback?: boolean
  setParentFocusZoneEnabled?: (enabled: boolean) => void
  panelWidth?: number
}

const InnerChatMessage = ({isLatestMessage, isStreaming, panelWidth, ...props}: InnerChatMessageProps) => {
  const state = useChatState()
  const manager = useChatManager()
  const {message} = useChatMessage()
  const author = findAuthor(message, state.currentUserLogin)
  const isCopilot = author.name === 'Copilot'
  const isUser = author.type === 'user'
  const isAI = isCopilot || isAgent(author)
  const isAgentError = isCopilot && !!message.agentErrors?.length
  const isError = !isAgentError && isCopilot && message.error ? message.error.isError : false
  const isLoading = state.isWaitingOnCopilot || props.isLoading || isStreaming
  const renderFeedback = isCopilot && !props.excludeFeedback && (!isLatestMessage || !isLoading)
  const focusableElements = useRef<HTMLElement[]>([])
  const myRef = useRef<HTMLDivElement>(null)
  const feedbackSubmitted = useRef(false)
  const isInterrupted = message.interrupted
  const hasClientConfirmations = message.clientConfirmations && message.clientConfirmations.length > 0

  const shouldShowMessageActions =
    !isError && (renderFeedback || (isCopilot && !!message.content && !isStreaming)) && !message.confirmations
  const shouldShowMessageActionsPlaceholder =
    isStreaming &&
    !isError &&
    !message.confirmations &&
    !shouldShowMessageActions &&
    isLatestMessage &&
    (!props.excludeFeedback || isCopilot)

  const fetchAgents = useCallback(async () => {
    return state.agentsPath ? await manager.fetchAgents(state.agentsPath) : []
  }, [manager, state.agentsPath])

  // true if there's something worth rendering (but we'll only render it if renderContentArea is true)
  const shouldRenderContentArea: boolean =
    (isCopilot && props.isLoading) ||
    Boolean(message.content) ||
    Boolean(message.references?.length) ||
    Boolean(message.confirmations?.length) ||
    Boolean(message.skillExecutions?.length) ||
    isError ||
    Boolean(isAgentError)

  // when a new message is streaming in we delay rendering the content area so the user always sees the blinky cursor
  const [renderContentArea, setRenderContentArea] = useState(shouldRenderContentArea && !(isAI && isStreaming))

  // start the timer to make renderContentArea true once there's something to render
  useEffect(() => {
    if (renderContentArea || !shouldRenderContentArea) return

    const timer = setTimeout(
      () => {
        setRenderContentArea(shouldRenderContentArea)
      },
      isAI && isLatestMessage ? 120 : 0, // allowing just enough time for the blinking cursor to always appear
    )

    return () => clearTimeout(timer)
  }, [isAI, isLatestMessage, renderContentArea, shouldRenderContentArea])

  useFocusZone(
    {
      containerRef: myRef,
      bindKeys: 128, // FocusKeys.Tab,
      focusableElementFilter: el => {
        // When the feedback dialog opens, the elements in it would be added to focusableElements.
        // We want to prevent that since focsuableElements is used to find out when to hand focus back
        // to the parent focusZone.
        if (!feedbackSubmitted.current && !focusableElements.current.includes(el)) {
          focusableElements.current.push(el)
        }
        return true
      },
      getNextFocusable: (direction, from) => {
        const currentIndex = focusableElements.current.indexOf(from as HTMLElement)
        if (direction === 'next') {
          if (currentIndex + 2 > focusableElements.current.length) {
            // We've tabbed past the end of this message, re-enable the parent focus zone
            // and focus the input.
            props.setParentFocusZoneEnabled?.(true)
            from?.setAttribute('tabindex', '-1')
            focusableElements.current[0]?.setAttribute('tabindex', '0')
            return props.inputRef?.current || undefined
          } else {
            // We've tabbed into the message, disable the parent focusZone.
            props.setParentFocusZoneEnabled?.(false)
            if (currentIndex !== -1) {
              // Return the next item as long as we're not in the feedback dialog.
              // FocusZone should do this, but it gets confused when we remove the feedback buttons.
              return focusableElements.current[currentIndex + 1]
            }
          }
        }
        if (direction === 'previous') {
          if (currentIndex === 1) {
            // We've shift+tabbed back to the message, re-enable the parent focuszone.
            props.setParentFocusZoneEnabled?.(true)
          }
          if (currentIndex > 0) {
            // Return the previous item as long as we're not in the feedback dialog.
            return focusableElements.current[currentIndex - 1]
          }
        }
        return undefined
      },
    },
    [],
  )

  useEffect(() => {
    if (isLatestMessage && isStreaming) {
      announce('Copilot is responding')
    }
  }, [isLatestMessage, isStreaming])

  useEffect(() => {
    if (isLatestMessage && !isStreaming && myRef.current) {
      announceFromElement(myRef.current)
    }
  }, [isLatestMessage, isStreaming])

  const onFeedbackSubmitted = useCallback(() => {
    // Remove the feedback buttons from the list of focusableElements, since they are replaced
    // with a disabled button.
    focusableElements.current = focusableElements.current.filter(
      (e: HTMLElement) => !e.classList.contains('feedback-action'),
    )
    feedbackSubmitted.current = true
  }, [])

  const handleConfirmationAction = useCallback(
    async (clientConfirmation: CopilotClientConfirmation, confirmationTitle: string) => {
      await manager.sendChatMessage(
        manager.getSelectedThread(state),
        `@${author.name} ${capitalize(clientConfirmation.state)} Confirmation: ${confirmationTitle}`,
        message.references ?? [],
        state.currentTopic,
        state.context,
        clientConfirmation,
      )
    },
    [manager, state, author.name, message.references],
  )

  return (
    <div
      className={clsx(
        'message-container',
        styles.chatMessage,
        isUser && styles.user,
        isAI && styles.ai,
        isLatestMessage && styles.latest,
      )}
      ref={myRef}
      // eslint-disable-next-line jsx-a11y/no-noninteractive-tabindex
      tabIndex={0}
    >
      {isCopilot ? (
        <CopilotBadge
          isLoading={isLoading && isLatestMessage}
          isError={isError && message.error?.type !== 'agentUnauthorized'}
          className={styles.avatar}
        />
      ) : isAI ? (
        <div className={clsx(styles.avatar, styles.agentAvatar)}>
          <GitHubAvatar src={author.avatarURL} size={22} />
        </div>
      ) : null}
      {isUser && message.references && (
        <ChatMessageReferences references={message.references} size="medium" className={styles.references} />
      )}
      <div className={styles.content}>
        {isCopilot && isLatestMessage && !renderContentArea ? (
          <span className={styles.blinkingCursor}>&#9611;</span>
        ) : null}
        {renderContentArea && (
          <>
            <div className="js-snippet-clipboard-copy-unpositioned">
              {isUser ? (
                <div className={styles.userFormat}>{message.content}</div>
              ) : (
                <>
                  {isCopilot &&
                    message.skillExecutions?.map((skillExecution, i) => {
                      return (
                        <FunctionCallBadge
                          // eslint-disable-next-line @eslint-react/no-array-index-key
                          key={i}
                          functionCall={skillExecution}
                          manager={manager}
                          panelWidth={panelWidth}
                        />
                      )
                    })}
                  {isCopilot && props.isLoading ? (
                    <>
                      <LoadingSkeleton variant="rounded" height="12px" width="random" />
                      <LoadingSkeleton variant="rounded" height="12px" width="random" />
                      <LoadingSkeleton variant="rounded" height="12px" width="random" />
                    </>
                  ) : (
                    !hasClientConfirmations && (
                      <MarkdownViewer
                        markdown={message.content ?? ''}
                        isStreaming={isLatestMessage && isLoading}
                        references={message.references ?? undefined}
                        annotations={message.copilotAnnotations}
                        openLinksInCurrentTab={false}
                        agents={state.agents}
                        fetchAgents={fetchAgents}
                        improvedCodeBlocks
                        messageId={message.id}
                      />
                    )
                  )}
                  {isError ? <ErrorMessage manager={manager} /> : null}
                  {isAgentError && message.agentErrors && <AgentErrors errors={message.agentErrors} />}
                  {isInterrupted ? (
                    <Flash
                      data-testid="chat-message-interrupted"
                      sx={{
                        fontSize: 1,
                        px: 2,
                        py: 1,
                      }}
                    >
                      Copilot was interrupted before it could finish this message.
                    </Flash>
                  ) : null}
                  {(isCopilot || isAgent(author)) &&
                    filterUniqueConfirmations(message.confirmations).map((confirmation, i) => {
                      return (confirmation.confirmation as CopilotCodeSearchConfirmation).name ===
                        'indexrepo' ? null : (
                        <Confirmation
                          confirmation={confirmation}
                          handleConfirmation={handleConfirmationAction}
                          // eslint-disable-next-line @eslint-react/no-array-index-key
                          key={i}
                          isLatestMessage={isLatestMessage}
                        />
                      )
                    })}
                </>
              )}
            </div>
            {shouldShowMessageActionsPlaceholder && <div className={styles.actionsPlaceholder} />}
            {shouldShowMessageActions && (
              <div className={styles.actions}>
                <Stack direction="horizontal" gap="none">
                  {renderFeedback && (
                    <Feedback
                      returnFocusRef={myRef}
                      setParentFocusZoneEnabled={props.setParentFocusZoneEnabled}
                      onFeedbackSubmitted={onFeedbackSubmitted}
                    />
                  )}
                  {isCopilot && !!message.content && !isStreaming && (
                    <CopyToClipboardButton
                      textToCopy={message.content ?? ''}
                      ariaLabel="Copy to clipboard"
                      size="medium"
                      className="d-flex flex-items-center"
                      onCopy={() =>
                        sendEvent('dotcom_chat.activate', {target: 'COPILOT_MESSAGE_COPY', mode: 'immersive'})
                      }
                    />
                  )}
                </Stack>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  )
}

const ChatMessageUnmemoized = ({message, ...props}: ChatMessageProps) => (
  <ChatMessageProvider message={message}>
    <InnerChatMessage {...props} />
  </ChatMessageProvider>
)

export const ChatMessage = memo(ChatMessageUnmemoized)

function ErrorMessage({manager}: {manager: CopilotChatManager}) {
  const {message} = useChatMessage()
  const {error} = message
  if (!error) return null
  switch (error.type) {
    case 'agentUnauthorized':
      return <AgentUnauthorizedError error={error} manager={manager} />
    case 'agentRequest':
      return <AgentErrors errors={[error.details]} />
    default:
      return (
        <Flash
          variant="warning"
          sx={{
            fontSize: 1,
            px: 2,
            py: 1,
          }}
        >
          <MarkdownRenderer markdown={error.message || 'Something went wrong'} />
        </Flash>
      )
  }
}

function AgentUnauthorizedError({error, manager}: {error: AgentUnauthorizedChatError; manager: CopilotChatManager}) {
  const {details} = error
  const [dismissed, setDismissed] = useState(false)
  const onDismiss = useCallback(() => {
    setDismissed(true)
    manager.dispatch({
      type: 'MESSAGE_ADDED',
      message: buildMessage({
        role: 'user',
        content: `Dismissed the connection with ${details.name}.`,
      }),
    })
    manager.dispatch({
      type: 'MESSAGE_ADDED',
      message: buildMessage({
        role: 'assistant',
        content: `I was unable to connect you to ${details.name} because you cancelled the authentication.`,
      }),
    })
  }, [details.name, manager])

  return (
    <div className="position-relative d-flex flex-column flex-items-center gap-3 border rounded-2 p-5">
      {!dismissed && (
        // eslint-disable-next-line primer-react/a11y-remove-disable-tooltip
        <IconButton
          aria-label="Close"
          className="position-absolute top-0 right-0 mt-2 mr-2"
          icon={XIcon}
          onClick={onDismiss}
          variant="invisible"
          unsafeDisableTooltip
        />
      )}
      <div className="d-flex flex-items-center gap-2">
        <MarkGithubIcon size={48} className="border circle borderColor-muted" />
        <LinkIcon className="fgColor-muted" />
        <img
          className={clsx('avatar', styles.agentUnauthorizedAvatar, 'border circle borderColor-muted')}
          src={details.avatar_url}
          alt={`icon for ${details.name}`}
        />
      </div>
      <p className="h4 m-0 text-center">Connect with {details.name}</p>
      <p className="fgColor-muted text-center">
        To use the {details.name} extension, you’ll need to connect your GitHub account to your {details.name} account.
      </p>
      {!dismissed && (
        <>
          <Button
            as="a"
            variant="primary"
            size="large"
            className="width-full"
            href={details.authorize_url}
            rel="noopener"
            target="_blank"
          >
            Connect
          </Button>
          <p className="fgColor-muted text-center f6 m-0">Click connect to be redirected to {details.authorize_url}</p>
        </>
      )}
    </div>
  )
}

function AgentErrors({errors}: {errors: CopilotAgentError[]}) {
  return (
    <div className="d-flex flex-column gap-2">
      {errors.map((error, i) => (
        // eslint-disable-next-line @eslint-react/no-array-index-key
        <div className="p-3 border rounded-2" key={i}>
          <div className="text-bold">
            <AlertFillIcon className="mr-1 fgColor-attention" /> {errorTitle(error)}
          </div>
          <div>{error.message}</div>
        </div>
      ))}
    </div>
  )
}

function errorTitle(error: CopilotAgentError) {
  if (error.type === 'http') {
    return `${error.code} ${error.identifier}`
  } else {
    return `${capitalize(error.type)} error`
  }
}

function capitalize(s: string) {
  return s.charAt(0).toUpperCase() + s.slice(1)
}

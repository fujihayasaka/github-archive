import {
  type ChatMessageContextProps,
  ChatMessageProvider,
  useChatMessage,
} from '@github-ui/copilot-chat/components/ChatMessageContext'
import {ChatMessageReferencesList} from '@github-ui/copilot-chat/components/ChatReferences'
import {Confirmation} from '@github-ui/copilot-chat/components/Confirmation'
import {CopilotBadge} from '@github-ui/copilot-chat/components/CopilotBadgeV2'
import {AgentErrors, ErrorMessage} from '@github-ui/copilot-chat/components/Errors'
import {Feedback} from '@github-ui/copilot-chat/components/Feedback'
import {FunctionCallBadge} from '@github-ui/copilot-chat/components/FunctionCallBadge'
import {messageFromFunctionCall} from '@github-ui/copilot-chat/components/FunctionLoadingUtils'
import {InterruptedBanner} from '@github-ui/copilot-chat/components/InterruptedBanner'
import {RetryButton} from '@github-ui/copilot-chat/components/RetryButton'
import {Toolbar} from '@github-ui/copilot-chat/components/Toolbar'
import {UserMessage} from '@github-ui/copilot-chat/components/UserMessage'
import {WithShimmerEffect} from '@github-ui/copilot-chat/components/WithShimmerEffect'
import {useChatState, useChatStateValues} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {useChatMessageBehavior} from '@github-ui/copilot-chat/hooks/use-chat-message-behavior'
import {useSelectedCustomCopilotId} from '@github-ui/copilot-chat/hooks/use-selected-custom-copilot-id'
import {filterUniqueConfirmations, srOnlyHeader} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {MAX_SUBTHREADS_PER_MESSAGE} from '@github-ui/copilot-chat/utils/copilot-chat-manager'
import {getParentMessage} from '@github-ui/copilot-chat/utils/copilot-chat-subthreading-helpers'
import {
  type CopilotChatMessage,
  type FigmaReference,
  type Invocation,
  NullMessageId,
} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {findCustomCopilot} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {sendEvent} from '@github-ui/hydro-analytics'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {testIdProps} from '@github-ui/test-id-props'
import {CommandIconButton} from '@github-ui/ui-commands'
import {useTrackingRef} from '@github-ui/use-tracking-ref'
import {PencilIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {clsx} from 'clsx'
import type React from 'react'
import {memo, type ReactNode, useCallback, useEffect, useMemo, useRef} from 'react'

import {useIsSharedThread} from '../hooks/use-is-shared-thread'
import {useNavigateToNewThread} from '../hooks/use-navigate-to-new-thread'
import {ChatImageAttachment} from './ChatImageAttachment'
import styles from './ChatMessage.module.css'
import {ChatMessageReferences} from './ChatMessageReferences'
import {ChatPagingComponent} from './ChatPagingComponent'
import type {Image, PreviewableContentIdentifier} from './ContentPreview/content-preview-types'
import {stripVersionFromId} from './ContentPreview/content-preview-types'
import {useContentPreview} from './ContentPreview/ContentPreviewContext'
import {MarkdownViewer, MemoizedMarkdownViewer} from './MarkdownViewer'
import {TimelineEvents, userMessageIsTimelineEvent} from './TimelineEvents'
import UserMessageEdit from './UserMessageEdit'

export interface ChatMessageProps extends ChatMessageContextProps, InnerChatMessageProps {}

type InnerChatMessageProps = {
  isLatestMessage?: boolean
  isSharedMessage?: boolean
  isViewingSharedThread?: boolean
  isFirstReply?: boolean
  inputRef?: React.RefObject<HTMLInputElement> | React.RefObject<HTMLTextAreaElement>
  isLoading?: boolean
  isStreaming?: boolean
  excludeFeedback?: boolean
  panelWidth?: number
  messageIndex: number
  autoOpenPreviewPane: boolean
}

const InnerChatMessage = ({
  excludeFeedback,
  inputRef,
  isLatestMessage,
  isFirstReply,
  isLoading: isLoadingProp,
  isStreaming,
  panelWidth,
  messageIndex,
  autoOpenPreviewPane,
}: InnerChatMessageProps) => {
  const {message} = useChatMessage()
  const manager = useChatManager()
  const state = useChatState()
  const {
    items: contentPreviewItems,
    versionedItems: contentPreviewVersionedItems,
    openItem: openContentPreviewItem,
    removeItems: removeContentPreviewItems,
    updateItem: updateContentPreviewItem,
    openItems: openContentPreviewItems,
    openItemsBeforeSubthreadChange,
    setOpenItemsBeforeSubthreadChange,
    enableLoadingState: enableContentPreviewLoadingState,
    disableLoadingState: disableContentPreviewLoadingState,
    previewPaneOpen,
  } = useContentPreview()

  /**
   * Effect for loading Figma design file previews in the side pane
   * as soon as they become available
   */
  useEffect(() => {
    const figmaReference: FigmaReference | undefined = state.currentReferences.find(ref => ref.type === 'figma')
    if (copilotFeatureFlags.immersiveFigmaIntegration && figmaReference) {
      const content: Image = {
        altText: figmaReference.title,
        type: 'image',
        url: figmaReference.fullImageUrl,
        id: `image:${figmaReference.fullImageUrl}`,
        messageId: message.id,
        name: figmaReference.title,
      }
      if (!contentPreviewItems.has(`image:${figmaReference.fullImageUrl}`)) {
        updateContentPreviewItem(content)
      }
    }
  }, [
    contentPreviewItems,
    message.id,
    message.references,
    previewPaneOpen,
    state.currentReferences,
    updateContentPreviewItem,
  ])

  const removeOutdatedContentPreviewItems = useCallback((): void => {
    // calculate the outdated messages we want to clear
    const messageIdsToClear = []
    let currentMessage: CopilotChatMessage | undefined = message
    while (currentMessage != null) {
      messageIdsToClear.push(currentMessage.id)
      if (currentMessage.selectedChildIndex !== undefined) {
        currentMessage = state.messages[currentMessage.selectedChildIndex]
      } else {
        currentMessage = undefined
      }
    }

    // File Browser uses file ids rather than message ids
    // so create a map of message ids to file ids to make the next step easier
    const messageIdsToFiles = new Map<string, PreviewableContentIdentifier[]>()
    for (const [k, v] of contentPreviewItems) {
      const files = messageIdsToFiles.get(v.messageId) || []
      files.push(k)
      messageIdsToFiles.set(v.messageId, files)
    }

    // using the outdated message ids, get the outdated file ids
    const fileIdsToClear: PreviewableContentIdentifier[] = []
    for (const messageId of messageIdsToClear) {
      const fileKeys = messageIdsToFiles.get(messageId)
      if (fileKeys) {
        for (const fileKey of fileKeys) {
          fileIdsToClear.push(fileKey)
        }
      }
    }

    // clear files with no message id. These may have been opened from clicking an input reference.
    for (const [id, previewItem] of contentPreviewItems) {
      if (previewItem.messageId === NullMessageId) {
        fileIdsToClear.push(id)
      }
    }

    setOpenItemsBeforeSubthreadChange([...openContentPreviewItems])

    // enable loading state if visible files will be cleared
    if (fileIdsToClear.some(fileIdToClear => openContentPreviewItems.includes(fileIdToClear))) {
      enableContentPreviewLoadingState()
    }

    removeContentPreviewItems(fileIdsToClear)
  }, [
    contentPreviewItems,
    enableContentPreviewLoadingState,
    message,
    openContentPreviewItems,
    removeContentPreviewItems,
    setOpenItemsBeforeSubthreadChange,
    state.messages,
  ])

  const {
    handleConfirmationAction,
    handleRetryErrorMessage,
    handleRetryCopilotResponse,
    handleEditUserMessage,
    hasClientConfirmations,
    isAgentError,
    isAI,
    isCopilot,
    isError,
    isInterrupted,
    isLoading: isCopilotLoading,
    isUser,
    myRef,
    rendererConfig,
    renderFeedback,
    shouldShowMessageActions,
    skillExecutionToUseForRespondingText,
    showRetryButton,
  } = useChatMessageBehavior({
    excludeFeedback,
    inputRef,
    isLatestMessage,
    isLoading: isLoadingProp,
    isStreaming,
    removeOutdatedContentPreviewItems,
  })

  const isViewingSharedThread = useIsSharedThread()
  const editing = state.editingMessage === message.id

  const shouldShowMessageActionsPlaceholder =
    isStreaming &&
    !isError &&
    !message.confirmations &&
    !shouldShowMessageActions &&
    isLatestMessage &&
    (!excludeFeedback || isAI)

  const parentMessage = getParentMessage(state.messages, message)
  const currentSubthread =
    (parentMessage?.childMessageIndexes?.findIndex(messageIdx => messageIdx === messageIndex) || 0) + 1 || 1
  const totalSubthreads = parentMessage?.childMessageIndexes?.length || 1
  const maxSubthreadsReached = totalSubthreads >= MAX_SUBTHREADS_PER_MESSAGE
  const maxMessagesReached = manager.maxMessagesReached()
  const hasSubthreads = totalSubthreads > 1

  const images = useMemo(
    () => message.mediaContent?.filter(media => media.mediaType.startsWith('image/')),
    [message.mediaContent],
  )
  const shouldShowImages = useMemo(
    () => (copilotFeatureFlags.attachImagesImmersive && typeof images !== 'undefined' && images.length > 0) || false,
    [images],
  )

  const shouldShowSharedMessageActions =
    shouldShowMessageActions && isViewingSharedThread && (isCopilot || hasSubthreads)

  const previousMessageIdRef = useRef<string | null>(null)
  const openLatestVersionRef = useTrackingRef((id: PreviewableContentIdentifier) => {
    const latestVersion = contentPreviewVersionedItems.get(stripVersionFromId(id))?.at(-1)
    if (latestVersion) openContentPreviewItem(latestVersion, false)
  })
  useEffect(() => {
    // When changing subthreads, we remove all the unmounted files as you'd expect. But if a file was open before
    // changing the subthread, we want to reopen the latest version after, so users can smoothly
    // navigate across. This is complicated by the fact that the files are only obtained after rendering the `FileBlock`.
    // So, after we render the last message, we want to open the latest versions. But this effect will run before
    // ContentPreviewContext updates the `contentPreviewVersionedItems`, so we have to delay with a timeout.

    // Messages are keyed by index, so the same component instance can render two separate messages when switching
    // subthreads, so we have to see if `message.id` changed rather than just running this on mount.
    if (previousMessageIdRef.current !== message.id && isLatestMessage && openItemsBeforeSubthreadChange.length > 0) {
      const timeout = setTimeout(() => {
        // using a callback ref ensures we get the latest version of contentPreviewVersionedItems when the timeout runs
        for (const openItem of openItemsBeforeSubthreadChange) openLatestVersionRef.current(openItem)

        disableContentPreviewLoadingState()
        setOpenItemsBeforeSubthreadChange([])
      })
      return () => clearTimeout(timeout)
    }
    previousMessageIdRef.current = message.id
  }, [
    disableContentPreviewLoadingState,
    message.id,
    openItemsBeforeSubthreadChange,
    isLatestMessage,
    setOpenItemsBeforeSubthreadChange,
    openLatestVersionRef,
  ])

  const handlePrevSubthreadClick = useCallback(() => {
    const currentIndex = currentSubthread - 1
    manager.setSelectedMessage(state.messages[parentMessage!.childMessageIndexes![currentIndex - 1]!]!)

    removeOutdatedContentPreviewItems()
  }, [currentSubthread, manager, parentMessage, removeOutdatedContentPreviewItems, state.messages])

  const handleNextSubthreadClick = useCallback(() => {
    const currentIndex = currentSubthread - 1
    manager.setSelectedMessage(state.messages[parentMessage!.childMessageIndexes![currentIndex + 1]!]!)

    removeOutdatedContentPreviewItems()
  }, [currentSubthread, manager, parentMessage, removeOutdatedContentPreviewItems, state.messages])

  const navigateToNewThread = useNavigateToNewThread()

  const {model: threadModel, availableModels} = useChatStateValues('model', 'availableModels')
  let messageModel = threadModel
  if (message.model) {
    const models = availableModels ?? [messageModel]
    messageModel = models.find(m => m.id === message.model) || messageModel
  }

  const isLatestUserMessage = isUser && state.messages.findLast(m => m.role === 'user')?.id === message.id
  const startEditing = () => manager.startEditingMessage(message.id)

  const customCopilotId = useSelectedCustomCopilotId()
  const customCopilotExists = Boolean(findCustomCopilot(state.customCopilots, customCopilotId))
  const customCopilotDisabled = !!customCopilotId && !customCopilotExists

  const subthreadingDisabled = maxSubthreadsReached || maxMessagesReached || customCopilotDisabled

  const waitingForCopilotContent = isCopilot && isCopilotLoading && isLatestMessage && !message.content

  const onWrapCodeLinesChange = useCallback(
    (wrap: boolean) => {
      manager.setWrapCodeLines(wrap)
    },
    [manager],
  )

  // while we're streaming we update the markdown viewer a lot and there's no need to memoize
  const MarkdownComponent = isStreaming ? MarkdownViewer : MemoizedMarkdownViewer

  return (
    <div
      className={clsx(
        'message-container',
        styles.chatMessage,
        isUser && styles.user,
        isAI && styles.ai,
        editing ? styles.editing : '',
        isLatestMessage && styles.latest,
      )}
      ref={myRef}
      {...testIdProps(`message-${isError ? 'error' : isStreaming ? 'streaming' : message.id}`)}
    >
      {isAI ? (
        <CopilotBadge
          isLoading={isCopilotLoading && isLatestMessage}
          isLoadingSkills={
            (message.skillExecutions ?? []).length > 0 && isCopilotLoading && message.content === '' && isLatestMessage
          }
          isError={isError && message.error?.type !== 'agentUnauthorized'}
          className={styles.avatar}
          mode={state.mode}
          isFirstMessage={isFirstReply}
          message={message.content || ''}
          createdAt={message.createdAt}
        />
      ) : null}
      {isUser && shouldShowImages && (
        <div className={images?.length === 4 ? styles.imageGrid : styles.imageRow}>
          {images?.map(image => (
            <ChatImageAttachment
              name={image?.name || 'Uploaded image'}
              messageId={message.id}
              src={image?.url || ''}
              key={image?.url || ''}
              alt={`Uploaded image${image?.name ? `: ${image.name}` : ''}`}
              mode={state.mode}
              squareView={images?.length >= 2}
            />
          ))}
        </div>
      )}
      {isUser && message.references && message.references.length > 0 && (
        <ChatMessageReferences
          className={styles.references}
          messageId={message.id}
          messageTimestamp={message.createdAt}
          messageIndex={messageIndex}
          references={message.references}
          size="medium"
        />
      )}
      {!editing && (
        <div className={styles.content}>
          {
            <>
              <div className={clsx('js-snippet-clipboard-copy-unpositioned', styles.messageArea)}>
                {isUser ? (
                  <UserMessage
                    accessibleHeader={srOnlyHeader('You', message.content ?? '')}
                    className={styles.userMessage}
                  />
                ) : (
                  <>
                    {!copilotFeatureFlags.newImmersiveReferencesUI &&
                      isCopilot &&
                      message.skillExecutions?.map((skillExecution, i) => {
                        return (
                          <FunctionCallBadge
                            // eslint-disable-next-line @eslint-react/no-array-index-key
                            key={i}
                            functionCall={skillExecution}
                            manager={manager}
                            panelWidth={panelWidth}
                            messageInterrupted={message.interrupted}
                          />
                        )
                      })}
                    {waitingForCopilotContent &&
                      (copilotFeatureFlags.newImmersiveReferencesUI ? (
                        <WithShimmerEffect className={clsx(styles.skillExecutionText, 'mb-2')}>
                          {`${messageFromFunctionCall(skillExecutionToUseForRespondingText)}...`}
                        </WithShimmerEffect>
                      ) : (
                        <>
                          <span className={styles.blinkingCursor}>▋</span>
                          <span className="sr-only">Waiting for reply…</span>
                        </>
                      ))}
                    {copilotFeatureFlags.newImmersiveReferencesUI &&
                      message.references &&
                      message.references.length > 0 &&
                      message.content && (
                        <ChatMessageReferencesList className="mb-2" references={message.references} isImmersive />
                      )}
                    {isCopilot && isLoadingProp ? (
                      <>
                        <LoadingSkeleton variant="rounded" height="12px" width="random" />
                        <LoadingSkeleton variant="rounded" height="12px" width="random" />
                        <LoadingSkeleton variant="rounded" height="12px" width="random" />
                      </>
                    ) : (
                      !hasClientConfirmations &&
                      message.content && (
                        // There is a boundary around the whole message which is useful for catching message logic errors,
                        // but if an error occurs while rendering markdown then we still want the user to be able to copy
                        // that markdown / retry / etc. So an identical boundary around just the renderer is useful.
                        <MessageErrorBoundary>
                          <MarkdownComponent
                            autoOpenPreviewPane={autoOpenPreviewPane}
                            markdown={message.content}
                            messageId={message.id}
                            messageIndex={messageIndex}
                            messageTimestamp={message.createdAt}
                            accessibleHeader={srOnlyHeader('Copilot', message.content ?? '')}
                            copilotAnnotations={message.copilotAnnotations}
                            wrapCodeLines={state.wrapCodeLines}
                            onWrapCodeLinesChange={onWrapCodeLinesChange}
                            {...rendererConfig}
                          />
                        </MessageErrorBoundary>
                      )
                    )}
                    {isError ? <ErrorMessage manager={manager} /> : null}
                    {isAgentError && message.agentErrors && <AgentErrors errors={message.agentErrors} />}
                    {isInterrupted ? (
                      <InterruptedBanner messageHasContent={!!message.content || !!message.skillExecutions?.length} />
                    ) : null}
                    {isAI &&
                      !waitingForCopilotContent &&
                      filterUniqueConfirmations(message.confirmations).map((confirmation, i) => {
                        const name = (confirmation.confirmation as Invocation).name
                        switch (name) {
                          case 'indexrepo':
                            return null
                          default:
                            return (
                              <Confirmation
                                confirmation={confirmation}
                                handleConfirmation={handleConfirmationAction}
                                // eslint-disable-next-line @eslint-react/no-array-index-key
                                key={i}
                                isLatestMessage={isLatestMessage}
                              />
                            )
                        }
                      })}
                  </>
                )}
                {hasSubthreads && !isLatestMessage && (
                  <div className={styles.messageSubthreadIndicator} data-testid="chat-paging-indicator">
                    {currentSubthread}/{totalSubthreads}
                  </div>
                )}
              </div>
              {shouldShowMessageActionsPlaceholder && <div className={styles.actionsPlaceholder} />}
              {!shouldShowMessageActions && showRetryButton && (
                <RetryButton handleRetryMessage={handleRetryErrorMessage} disabled={subthreadingDisabled} />
              )}
              {shouldShowMessageActions && !isViewingSharedThread && (
                <Toolbar aria-label="Message tools" className={styles.actions} data-testid="nonshared-toolbar">
                  {isUser &&
                    (isLatestUserMessage ? (
                      <CommandIconButton
                        // This will show the keybinding hint, but we still have to bind the onClick handler because
                        // this button is outside the command scope (which is only the input - pressing the up arrow
                        // only works when the input is focused)
                        commandId="copilot-chat:edit-last-message"
                        variant="invisible"
                        aria-label="Edit message"
                        onClick={startEditing}
                        icon={PencilIcon}
                        disabled={subthreadingDisabled}
                        {...testIdProps('edit-message-button')}
                      />
                    ) : (
                      <IconButton
                        variant="invisible"
                        aria-label="Edit message"
                        onClick={startEditing}
                        icon={PencilIcon}
                        disabled={subthreadingDisabled}
                        {...testIdProps('edit-message-button')}
                      />
                    ))}
                  {isCopilot && (
                    <>
                      {renderFeedback && <Feedback iconSize="medium" />}
                      {!!message.content && !isStreaming && (
                        <CopyToClipboardButton
                          textToCopy={message.content ?? ''}
                          ariaLabel="Copy to clipboard"
                          size="medium"
                          className="d-flex flex-items-center"
                          onCopy={() =>
                            sendEvent('dotcom_chat.activate', {target: 'RESPONSE_ACTION_COPY', mode: 'immersive'})
                          }
                        />
                      )}
                    </>
                  )}
                  {showRetryButton && isError ? (
                    <RetryButton handleRetryMessage={handleRetryErrorMessage} disabled={subthreadingDisabled} />
                  ) : (
                    isAI &&
                    !isError &&
                    !message.clientSide && (
                      <RetryButton
                        handleRetryMessage={handleRetryCopilotResponse}
                        disabled={subthreadingDisabled}
                        showModelPicker={!!availableModels && availableModels.length > 1}
                        model={messageModel}
                        navigateToNewThread={navigateToNewThread}
                      />
                    )
                  )}
                  {hasSubthreads && (
                    <ChatPagingComponent
                      currentPage={currentSubthread}
                      totalPages={totalSubthreads}
                      onPrev={handlePrevSubthreadClick}
                      onNext={handleNextSubthreadClick}
                      isUserMessage={isUser}
                      disabled={state.isWaitingOnCopilot}
                    />
                  )}
                </Toolbar>
              )}

              {/* When viewing a shared thread conversation, show copy to clipboard for Copilot responses and show
                  subthread navigation if a message has subthreads. Edit, feedback, retry should never show up. */}
              {shouldShowSharedMessageActions && (
                <Toolbar aria-label="Message tools" className={styles.sharedThreadActions} data-testid="shared-toolbar">
                  {isCopilot && (
                    <>
                      {!!message.content && !isStreaming && (
                        <CopyToClipboardButton
                          textToCopy={message.content ?? ''}
                          ariaLabel="Copy to clipboard"
                          size="medium"
                          className="d-flex flex-items-center actions"
                          onCopy={() =>
                            sendEvent('dotcom_chat.activate', {target: 'RESPONSE_ACTION_COPY', mode: 'immersive'})
                          }
                        />
                      )}
                    </>
                  )}
                  {hasSubthreads && (
                    <ChatPagingComponent
                      currentPage={currentSubthread}
                      totalPages={totalSubthreads}
                      onPrev={handlePrevSubthreadClick}
                      onNext={handleNextSubthreadClick}
                      isUserMessage={isUser}
                      disabled={state.isWaitingOnCopilot}
                    />
                  )}
                </Toolbar>
              )}
            </>
          }
        </div>
      )}
      {editing && (
        <UserMessageEdit
          messageContent={message.content || ''}
          onSubmit={handleEditUserMessage}
          onCancel={() => manager.cancelEditingMessage()}
          disableSubmit={state.isWaitingOnCopilot}
        />
      )}
    </div>
  )
}

const MessageErrorBoundary = ({children}: {children: ReactNode}) => (
  <ErrorBoundary
    fallback={
      <Banner
        className={styles.errorFallback}
        variant="warning"
        title="Message cannot be displayed"
        description="An unknown error occurred while attempting to display this message."
      />
    }
  >
    {children}
  </ErrorBoundary>
)

const ChatMessageUnmemoized = ({
  message,
  messageIndex,
  isSharedMessage,
  isLatestMessage,
  ...props
}: ChatMessageProps) => {
  const isViewingSharedThread = useIsSharedThread()
  return (
    <ChatMessageProvider message={message}>
      {!userMessageIsTimelineEvent(message) && (
        <InnerChatMessage
          {...props}
          messageIndex={messageIndex}
          isSharedMessage={isSharedMessage}
          isLatestMessage={isLatestMessage}
          isViewingSharedThread={isViewingSharedThread}
        />
      )}
      <TimelineEvents
        message={message}
        messageIndex={messageIndex}
        isViewingSharedThread={isViewingSharedThread}
        isSharedMessage={isSharedMessage}
        isLatestMessage={isLatestMessage}
      />
    </ChatMessageProvider>
  )
}

export const ChatMessage = memo(function ChatMessage(props: ChatMessageProps) {
  return (
    <MessageErrorBoundary>
      <ChatMessageUnmemoized {...props} />
    </MessageErrorBoundary>
  )
})

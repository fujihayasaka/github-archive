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
import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {useChatMessageBehavior} from '@github-ui/copilot-chat/hooks/use-chat-message-behavior'
import {filterUniqueConfirmations} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {MAX_SUBTHREADS_PER_MESSAGE} from '@github-ui/copilot-chat/utils/copilot-chat-manager'
import {getParentMessage} from '@github-ui/copilot-chat/utils/copilot-chat-subthreading-helpers'
import {
  type CopilotChatMessage,
  type CopilotCodeSearchConfirmation,
  type FigmaReference,
  NullMessageId,
} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {MarkdownRenderer} from '@github-ui/copilot-markdown'
import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {sendEvent} from '@github-ui/hydro-analytics'
import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {testIdProps} from '@github-ui/test-id-props'
import {LinkIcon, PencilIcon, RepoForkedIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {clsx} from 'clsx'
import type React from 'react'
import {memo, useCallback, useEffect, useState} from 'react'

import {useIsSharedThread} from '../hooks/use-is-shared-thread'
import {ChatImageAttachment} from './ChatImageAttachment'
import styles from './ChatMessage.module.css'
import {ChatMessageReferences} from './ChatMessageReferences'
import {ChatPagingComponent} from './ChatPagingComponent'
import type {Image, PreviewableContentIdentifier} from './ContentPreview/content-preview-types'
import {stripVersionFromId} from './ContentPreview/content-preview-types'
import {useContentPreview} from './ContentPreview/ContentPreviewContext'
import {MarkdownViewer} from './MarkdownViewer'
import {TimelineEditEntriesForMessage} from './TimelineEditEntry'
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
    messagesBeforeSubthreadChange,
    setMessagesBeforeSubthreadChange,
    enableLoadingState: enableContentPreviewLoadingState,
    disableLoadingState: disableContentPreviewLoadingState,
    openPreviewPane,
    closePreviewPane,
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

  useEffect(() => {
    if (copilotFeatureFlags.immersiveFigmaIntegration) {
      if (contentPreviewItems.size > 0) {
        openPreviewPane()
      } else {
        closePreviewPane()
      }
    }
  }, [closePreviewPane, contentPreviewItems, openPreviewPane])

  const removeOutdatedContentPreviewItems = useCallback((): void => {
    enableContentPreviewLoadingState()

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
    setMessagesBeforeSubthreadChange(state.messages.map(m => m.id))

    // switch to previous version of files being removed if open and one exists
    for (const filedIdToClear of fileIdsToClear) {
      if (openContentPreviewItems.indexOf(filedIdToClear) > -1) {
        // get the latest version that's not being removed
        const fileIdToClearName = stripVersionFromId(filedIdToClear)
        const fileVersions = contentPreviewVersionedItems.get(fileIdToClearName) ?? []
        for (let i = fileVersions.length - 1; i >= 0; i--) {
          const fileVersion = fileVersions[i] as PreviewableContentIdentifier
          if (fileVersion && fileIdsToClear.indexOf(fileVersion) === -1) {
            openContentPreviewItem(fileVersion)
            break
          }
        }
      }
    }

    removeContentPreviewItems(fileIdsToClear)
  }, [
    contentPreviewItems,
    contentPreviewVersionedItems,
    enableContentPreviewLoadingState,
    message,
    openContentPreviewItems,
    removeContentPreviewItems,
    openContentPreviewItem,
    setMessagesBeforeSubthreadChange,
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
    onFeedbackSubmitted,
    renderContentArea,
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

  const isSharedThread = useIsSharedThread()
  const [editing, setEditing] = useState(false)

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

  const image = message.mediaContent?.find(media => media.mediaType.startsWith('image/'))
  const shouldShowImages = (copilotFeatureFlags.attachImagesImmersive && typeof image !== 'undefined') || false

  useEffect(() => {
    // This is the last message to load; set the selected file versions and hide loading UI
    if (message.selectedChildIndex === undefined) {
      if (messagesBeforeSubthreadChange.includes(message.id)) {
        for (const openItem of openItemsBeforeSubthreadChange) {
          const fileVersions = contentPreviewVersionedItems.get(stripVersionFromId(openItem))
          if (fileVersions) {
            const lastVersion = fileVersions.at(-1)
            if (lastVersion) {
              openContentPreviewItem(lastVersion, false)
            }
          }
        }
      }
      disableContentPreviewLoadingState()
    }
  }, [
    contentPreviewVersionedItems,
    disableContentPreviewLoadingState,
    message.id,
    message.selectedChildIndex,
    openContentPreviewItems,
    openContentPreviewItem,
    messagesBeforeSubthreadChange,
    openItemsBeforeSubthreadChange,
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
        <ChatImageAttachment
          name={image?.name || 'Uploaded image'}
          messageId={message.id}
          src={image?.url || ''}
          alt={`Uploaded image${image?.name ? `: ${image.name}` : ''}`}
        />
      )}
      {isUser && message.references && (
        <ChatMessageReferences
          className={styles.references}
          messageID={message.id}
          messageTimestamp={message.createdAt}
          references={message.references}
          size="medium"
        />
      )}
      {!editing && (
        <div className={styles.content}>
          {isCopilot && isLatestMessage && !renderContentArea ? <MarkdownRenderer markdown="" isStreaming /> : null}
          {renderContentArea && (
            <>
              <div className={clsx('js-snippet-clipboard-copy-unpositioned', styles.messageArea)}>
                {isUser ? (
                  <UserMessage className={styles.userMessage}>{message.content ?? ''}</UserMessage>
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
                    {copilotFeatureFlags.newImmersiveReferencesUI && (
                      <>
                        {isCopilot && isCopilotLoading && isLatestMessage && (
                          <WithShimmerEffect className={clsx(styles.skillExecutionText, 'mb-2 mt-1')}>
                            {`${messageFromFunctionCall(skillExecutionToUseForRespondingText)}...`}
                          </WithShimmerEffect>
                        )}
                        {message.references && message.references.length > 0 && (
                          <ChatMessageReferencesList className="mb-3" references={message.references} isImmersive />
                        )}
                      </>
                    )}
                    {isCopilot && isLoadingProp ? (
                      <>
                        <LoadingSkeleton variant="rounded" height="12px" width="random" />
                        <LoadingSkeleton variant="rounded" height="12px" width="random" />
                        <LoadingSkeleton variant="rounded" height="12px" width="random" />
                      </>
                    ) : (
                      !hasClientConfirmations && (
                        <MarkdownViewer
                          autoOpenPreviewPane={autoOpenPreviewPane}
                          markdown={message.content ?? ''}
                          messageId={message.id}
                          messageIndex={messageIndex}
                          messageTimestamp={message.createdAt}
                          {...rendererConfig}
                        />
                      )
                    )}
                    {isError ? <ErrorMessage manager={manager} /> : null}
                    {isAgentError && message.agentErrors && <AgentErrors errors={message.agentErrors} />}
                    {isInterrupted ? (
                      <InterruptedBanner messageHasContent={!!message.content || !!message.skillExecutions?.length} />
                    ) : null}
                    {isAI &&
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
                {copilotFeatureFlags.immersiveSubthreading && totalSubthreads > 1 && !isLatestMessage && (
                  <div className={styles.messageSubthreadIndicator} data-testid="chat-paging-indicator">
                    {currentSubthread}/{totalSubthreads}
                  </div>
                )}
              </div>
              {shouldShowMessageActionsPlaceholder && <div className={styles.actionsPlaceholder} />}
              {!shouldShowMessageActions && showRetryButton && (
                <RetryButton
                  handleRetryMessage={handleRetryErrorMessage}
                  disabled={maxSubthreadsReached || maxMessagesReached}
                />
              )}
              {shouldShowMessageActions && !isSharedThread && (
                <Toolbar aria-label="Message tools" className={styles.actions}>
                  {copilotFeatureFlags.immersiveSubthreading && isUser && (
                    <IconButton
                      variant="invisible"
                      aria-label="Edit message"
                      onClick={() => {
                        setEditing(true)
                        sendEvent('dotcom_chat.activate', {target: 'USER_MESSAGE_ACTION_EDIT', mode: 'immersive'})
                      }}
                      icon={PencilIcon}
                      disabled={maxSubthreadsReached || maxMessagesReached}
                      {...testIdProps('edit-message-button')}
                    />
                  )}
                  {isCopilot && (
                    <>
                      {renderFeedback && (
                        <Feedback iconSize="medium" returnFocusRef={myRef} onFeedbackSubmitted={onFeedbackSubmitted} />
                      )}
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
                    <RetryButton
                      handleRetryMessage={handleRetryErrorMessage}
                      disabled={maxSubthreadsReached || maxMessagesReached}
                    />
                  ) : (
                    copilotFeatureFlags.immersiveSubthreading &&
                    isAI &&
                    !isError &&
                    !message.clientSide && (
                      <RetryButton
                        handleRetryMessage={handleRetryCopilotResponse}
                        disabled={maxSubthreadsReached || maxMessagesReached}
                        showModelPicker={copilotFeatureFlags.retryModelPicker}
                        modelName={message.model}
                      />
                    )
                  )}
                  {copilotFeatureFlags.immersiveSubthreading && totalSubthreads > 1 && (
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

              {/* When viewing a shared thread conversation, only show copy to clipboard for Copilot responses.
                  All other message actions (edit, feedback, retry, navigation) should be disabled */}
              {isCopilot && shouldShowMessageActions && isSharedThread && (
                <Toolbar aria-label="Message tools" className={styles.sharedThreadActions}>
                  {
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
                  }
                </Toolbar>
              )}
            </>
          )}
        </div>
      )}
      {editing && copilotFeatureFlags.immersiveSubthreading && (
        <UserMessageEdit
          messageContent={message.content || ''}
          handleEditUserMessage={handleEditUserMessage}
          setEditing={setEditing}
          disableSubmit={state.isWaitingOnCopilot}
        />
      )}
    </div>
  )
}

const ChatMessageUnmemoized = ({message, ...props}: ChatMessageProps) => {
  const isViewingSharedThread = useIsSharedThread()
  return (
    <ChatMessageProvider message={message}>
      <TimelineEditEntriesForMessage message={message} messageIndex={props.messageIndex} />
      <InnerChatMessage {...props} isViewingSharedThread={isViewingSharedThread} />
      {props.isSharedMessage && !isViewingSharedThread && (
        <div className={styles.sharedMessageCheckpoint}>
          <LinkIcon className={styles.icon} /> Messages up to this point are included in shared link
        </div>
      )}

      {props.isLatestMessage && copilotFeatureFlags.copilotDuplicateThread && isViewingSharedThread && (
        <div className={styles.sharedMessageCheckpoint}>
          <RepoForkedIcon className={styles.icon} /> Messages beyond this point will start a new private conversation.
        </div>
      )}
    </ChatMessageProvider>
  )
}

export const ChatMessage = memo(ChatMessageUnmemoized)

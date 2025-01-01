import {announce, announceFromElement} from '@github-ui/aria-live'
import type {MarkdownRendererProps} from '@github-ui/copilot-markdown'
import {sendEvent} from '@github-ui/hydro-analytics'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'

import {useChatMessage} from '../components/ChatMessageContext'
import {codeAnnotationsExtension} from '../markdown-extensions/code-annotations/code-annotations'
import {findAuthor, isAgent} from '../utils/copilot-chat-helpers'
import type {CopilotClientConfirmation, SkillExecution} from '../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {capitalize} from '../utils/string'

export function useChatMessageBehavior({
  excludeFeedback,
  isLatestMessage,
  isSharedMessage,
  isLoading,
  isStreaming,
  removeOutdatedContentPreviewItems,
}: {
  excludeFeedback?: boolean
  inputRef?: React.RefObject<HTMLInputElement> | React.RefObject<HTMLTextAreaElement>
  isLatestMessage?: boolean
  isSharedMessage?: boolean
  isLoading?: boolean
  isStreaming?: boolean
  excludeReferencesFromFocusZone?: boolean
  removeOutdatedContentPreviewItems?: () => void
}) {
  const {message} = useChatMessage()
  const state = useChatState()
  const manager = useChatManager()
  const author = findAuthor(message, state.currentUserLogin)
  const isCopilot = author.name === 'Copilot'
  const isUser = author.type === 'user'
  const isAI = isCopilot || isAgent(author)
  const isAgentError = isCopilot && !!message.agentErrors?.length
  const isError = !isAgentError && isCopilot && message.error ? message.error.isError : false
  const isLoadingContent = state.isWaitingOnCopilot || isLoading || isStreaming
  const renderFeedback = isCopilot && !excludeFeedback && (!isLatestMessage || !isLoadingContent) && !isError
  const focusableElements = useRef<HTMLElement[]>([])
  const myRef = useRef<HTMLDivElement>(null)
  const feedbackSubmitted = useRef(false)
  const isInterrupted = message.interrupted
  const hasClientConfirmations = message.clientConfirmations && message.clientConfirmations.length > 0
  const isErrorRetryable = isError && message.error?.retryable
  const [shownSkillExecutionsForRespondingText, setShownSkillExecutionsForRespondingText] = useState<SkillExecution[]>(
    [],
  )
  const [skillExecutionToUseForRespondingText, setSkillExecutionToUseForRespondingText] = useState<
    SkillExecution | undefined
  >(undefined)
  const showRetryButton = (isErrorRetryable || isInterrupted) && isLatestMessage

  const extensions = useMemo(() => {
    return [
      codeAnnotationsExtension({
        publicCodeReferences: message.copilotAnnotations?.PublicCodeReference ?? [],
        vulnerabilities: message.copilotAnnotations?.CodeVulnerability ?? [],
      }),
    ]
  }, [message.copilotAnnotations])

  const rendererConfig: Omit<MarkdownRendererProps, 'markdown'> = {
    extensions,
    openLinksInCurrentTab: state.mode === 'assistive',
    isStreaming: isLatestMessage && isLoadingContent,
  }

  const shouldShowMessageActions =
    (!isError && (renderFeedback || (isAI && !!message.content && !isStreaming)) && !message.confirmations) ||
    (((isUser && !isLatestMessage) || (isError && isLatestMessage)) && copilotFeatureFlags.immersiveSubthreading)

  const shouldRenderContentArea: boolean =
    (isCopilot && isLoading) ||
    Boolean(message.content) ||
    Boolean(message.references?.length) ||
    Boolean(message.confirmations?.length) ||
    Boolean(message.skillExecutions?.length) ||
    isError ||
    Boolean(isAgentError) ||
    Boolean(isInterrupted)

  const [renderContentArea, setRenderContentArea] = useState(shouldRenderContentArea && !(isAI && isStreaming))

  useEffect(() => {
    if (renderContentArea || !shouldRenderContentArea) return

    const timer = setTimeout(
      () => {
        setRenderContentArea(shouldRenderContentArea)
      },
      isAI && isLatestMessage ? 120 : 0,
    )

    return () => clearTimeout(timer)
  }, [isAI, isLatestMessage, renderContentArea, shouldRenderContentArea])

  const activeSkillAnimationTime = 2000
  const lastSkillUpdateTime = useRef<number>(0)

  useEffect(() => {
    const skillExecutionToUse = (message.skillExecutions ?? []).find(
      skillExecution =>
        !shownSkillExecutionsForRespondingText.some(
          (shownSkillExecution: {slug: string}) => shownSkillExecution.slug === skillExecution.slug,
        ),
    )

    if (skillExecutionToUse) {
      const timeElapsedSinceLastUpdate = Date.now() - lastSkillUpdateTime.current
      const timeToWait = Math.max(0, activeSkillAnimationTime - timeElapsedSinceLastUpdate)
      const timer = setTimeout(() => {
        lastSkillUpdateTime.current = Date.now()
        setShownSkillExecutionsForRespondingText([...shownSkillExecutionsForRespondingText, skillExecutionToUse])
        setSkillExecutionToUseForRespondingText(skillExecutionToUse)
      }, timeToWait)
      return () => clearTimeout(timer)
    }
  }, [message.skillExecutions, shownSkillExecutionsForRespondingText])

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
    async (
      clientConfirmation: CopilotClientConfirmation,
      confirmationTitle: string,
      onSubmit?: (accepted: boolean) => void,
    ) => {
      if (onSubmit) {
        onSubmit(clientConfirmation.state === 'accepted')
      } else {
        await manager.sendChatMessage({
          thread: manager.getSelectedThread(state),
          content: `@${author.name} ${capitalize(clientConfirmation.state)} Confirmation: ${confirmationTitle}`,
          references: message.references ?? [],
          topic: state.currentTopic,
          context: state.context,
          confirmations: clientConfirmation,
          customInstructions: state.customInstructions,
          model: state.model,
        })
      }
    },
    [manager, state, author.name, message.references],
  )

  const handleRetryErrorMessage = useCallback(async () => {
    const thread = manager.getSelectedThread(state)
    if (!thread) return

    if (copilotFeatureFlags.immersiveSubthreading && removeOutdatedContentPreviewItems) {
      removeOutdatedContentPreviewItems()
    }

    sendEvent('dotcom_chat.activate', {target: 'RESPONSE_ACTION_RETRY', mode: state.mode})
    await manager.retryLastUnsuccessfulChatMessage(thread)
  }, [manager, state, removeOutdatedContentPreviewItems])

  const handleRetryCopilotResponse = useCallback(async () => {
    const thread = manager.getSelectedThread(state)
    if (!thread) return

    if (copilotFeatureFlags.immersiveSubthreading && removeOutdatedContentPreviewItems) {
      removeOutdatedContentPreviewItems()
    }

    sendEvent('dotcom_chat.activate', {target: 'RESPONSE_ACTION_RETRY_FOR_NEW_SUBTHREAD', mode: state.mode})
    await manager.retryUserChatMessage(thread, message)
  }, [manager, state, message, removeOutdatedContentPreviewItems])

  const handleEditUserMessage = useCallback(
    async (editedValue: string) => {
      const thread = manager.getSelectedThread(state)
      if (!thread) return

      if (copilotFeatureFlags.immersiveSubthreading && removeOutdatedContentPreviewItems) {
        removeOutdatedContentPreviewItems()
      }

      await manager.editUserChatMessage(thread, message, editedValue)
    },
    [manager, state, message, removeOutdatedContentPreviewItems],
  )

  return {
    author,
    removeOutdatedContentPreviewItems,
    feedbackSubmitted,
    focusableElements,
    handleConfirmationAction,
    handleRetryErrorMessage,
    handleRetryCopilotResponse,
    handleEditUserMessage,
    hasClientConfirmations,
    isCopilot,
    isUser,
    isAI,
    isAgentError,
    isError,
    isInterrupted,
    isLoading: isLoadingContent,
    isSharedMessage,
    myRef,
    onFeedbackSubmitted,
    renderContentArea,
    rendererConfig,
    renderFeedback,
    shouldRenderContentArea,
    shouldShowMessageActions,
    shownSkillExecutionsForRespondingText,
    skillExecutionToUseForRespondingText,
    showRetryButton,
  }
}

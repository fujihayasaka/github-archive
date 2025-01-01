import {announce, announceFromElement} from '@github-ui/aria-live'
import type {MarkdownRendererProps} from '@github-ui/copilot-markdown'
import {sendEvent} from '@github-ui/hydro-analytics'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'

import {useChatMessage} from '../components/ChatMessageContext'
import {usePlugin} from '../plugin/ImmersivePluginsProvider'
import {findAuthor, isAgent} from '../utils/copilot-chat-helpers'
import type {CopilotChatModel, CopilotClientConfirmation, SkillExecution} from '../utils/copilot-chat-types'
import {useChatState, useChatStateValue} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {getSelectedThread} from '../utils/get-selected-thread'
import {capitalize} from '../utils/string'

export function useChatMessageBehavior({
  excludeFeedback,
  inputRef,
  isLatestMessage,
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
  const plugin = usePlugin(useChatStateValue('activePlugin'))

  const author = findAuthor(message, state.currentUserLogin)
  const isCopilot = author.name === 'Copilot'
  const isUser = author.type === 'user'
  const isAI = isCopilot || isAgent(author)
  const isAgentError = isCopilot && !!message.agentErrors?.length
  const isError = !isAgentError && isCopilot && message.error ? message.error.isError : false
  const isLoadingContent = state.isWaitingOnCopilot || isLoading || isStreaming
  const renderFeedback = isCopilot && !excludeFeedback && (!isLatestMessage || !isLoadingContent) && !isError
  const myRef = useRef<HTMLDivElement>(null)
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

  const pluginExtensions = useMemo(() => {
    return plugin?.markdownExtensions ? plugin.markdownExtensions.map(extension => extension()) : []
  }, [plugin])

  const rendererConfig: Omit<MarkdownRendererProps, 'markdown'> = {
    openLinksInCurrentTab: state.mode === 'assistive',
    isStreaming: isLatestMessage && isLoadingContent,
    extensions: pluginExtensions,
  }

  const shouldShowMessageActions =
    (!isError &&
      (renderFeedback || (isAI && !!message.content && !isStreaming)) &&
      (!isUser || !message.confirmations)) ||
    (isUser && !isLatestMessage) ||
    (isError && isLatestMessage)

  const activeSkillAnimationTime = 2000
  const lastSkillUpdateTime = useRef<number>(0)

  useEffect(() => {
    const skillExecutionToUse = (message.skillExecutions ?? []).find(
      skillExecution =>
        !shownSkillExecutionsForRespondingText.some(
          (shownSkillExecution: {slug: string; statusMessage?: string}) =>
            shownSkillExecution.slug === skillExecution.slug &&
            shownSkillExecution.statusMessage === skillExecution.statusMessage,
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
          thread: getSelectedThread(state),
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

  const focusChatInput = useCallback(() => {
    // setTimeout to delay so we pull focus after ModelPicker's ActionMenu
    // tries to return focus to its (now nonexistent) anchor
    window.setTimeout(() => inputRef?.current?.focus(), 1)
  }, [inputRef])

  const handleRetryErrorMessage = useCallback(async () => {
    const thread = getSelectedThread(state)
    if (!thread) return

    removeOutdatedContentPreviewItems?.()
    focusChatInput()

    sendEvent('dotcom_chat.activate', {target: 'RESPONSE_ACTION_RETRY', mode: state.mode})
    await manager.retryLastUnsuccessfulChatMessage(thread)
  }, [manager, state, removeOutdatedContentPreviewItems, focusChatInput])

  const handleRetryCopilotResponse = useCallback(
    async (model?: CopilotChatModel) => {
      const thread = getSelectedThread(state)
      if (!thread) return

      removeOutdatedContentPreviewItems?.()
      focusChatInput()

      sendEvent('dotcom_chat.activate', {
        target: 'RESPONSE_ACTION_RETRY_FOR_NEW_SUBTHREAD',
        mode: state.mode,
      })
      await manager.retryUserChatMessage(thread, message, model)
    },
    [manager, state, message, removeOutdatedContentPreviewItems, focusChatInput],
  )

  const handleEditUserMessage = useCallback(
    async (editedValue: string) => {
      const thread = getSelectedThread(state)
      if (!thread) return

      removeOutdatedContentPreviewItems?.()

      await manager.editUserChatMessage(thread, message, editedValue)
    },
    [manager, state, message, removeOutdatedContentPreviewItems],
  )

  return {
    author,
    removeOutdatedContentPreviewItems,
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
    myRef,
    rendererConfig,
    renderFeedback,
    shouldShowMessageActions,
    skillExecutionToUseForRespondingText,
    showRetryButton,
  }
}

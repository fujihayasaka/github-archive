import {sendEvent} from '@github-ui/hydro-analytics'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import type {FormEvent, RefObject} from 'react'
import type React from 'react'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'
import {useLocation, useSearchParams} from 'react-router-dom'

import type {CopilotChatMode} from '../utils/copilot-chat-types'
import {copilotLocalStorage} from '../utils/copilot-local-storage'
import {executePotentialSlashCommand} from '../utils/copilot-slash-commands'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'

const MAX_HEIGHT = 300

interface UseChatInputProps {
  textAreaRef?: RefObject<HTMLTextAreaElement>
  onSubmit?: (text: string) => Promise<void>
  isLoading?: boolean
  clearPastedFile?: () => void
}

interface UseChatInputReturn {
  /** true if the user has provided input since the last message was sent */
  typingHasStarted: boolean
  /** reference to the input textarea */
  textAreaRef: RefObject<HTMLTextAreaElement>
  /** reference to the textarea preview div, which is used to display rich text in the input */
  textareaPreviewRef: RefObject<HTMLDivElement>
  /** container whose height can be adjusted to match the user's input */
  textAreaPreviewContainerRef: RefObject<HTMLDivElement>
  /** the current user input */
  text: string
  /** sets the contents of the input */
  setText: React.Dispatch<React.SetStateAction<string>>
  /** function to call to send a message */
  handleSubmit: (e?: FormEvent) => Promise<void>
  /** function to call to send a message to a new thread */
  handleSubmitToNewThread: () => Promise<void>
  /** handler for the onScroll event of the input textarea */
  handleScroll: () => void
  /** handler for the onChange event of the input textarea */
  handleChange: (e: React.ChangeEvent<HTMLTextAreaElement>) => void
  /** call to stop response streaming */
  handleStop: () => Promise<void>
  /** handler to move cursor to the end of prompt loaded from query params */
  handleFocus: (e: React.FocusEvent<HTMLTextAreaElement>) => void
}

/**
 * Does a bunch of stuff, too much really, to manage a chat input for a copilot chat.
 */
export function useChatInput(props: UseChatInputProps): UseChatInputReturn {
  const state = useChatState()
  const manager = useChatManager()
  const {selectedThreadID, mode, autoSubmit, model} = state
  const {clearPastedFile} = props
  const savedUserMessage = copilotLocalStorage.getSavedMessage(selectedThreadID)
  const savedUserMessageOnError = copilotLocalStorage.getSavedUserMessageOnError(selectedThreadID)
  const {pathname} = useLocation()
  const [searchParams, setSearchParams] = useSearchParams()
  const [text, setText] = useState(() => {
    // we figure out the initial text here so it will be available in the first render
    const prompt = getPromptFromSearchParams(state.mode, pathname, searchParams)
    return prompt ?? savedUserMessageOnError ?? savedUserMessage ?? ''
  })

  const [typingHasStarted, setTypingHasStarted] = useState(false)
  const internalRef = useRef<HTMLTextAreaElement>(null)
  const textAreaRef = props.textAreaRef || internalRef
  const textareaPreviewRef = useRef<HTMLDivElement>(null)
  const textAreaPreviewContainerRef = useRef<HTMLDivElement>(null)
  const recallIndex = useRef(0)

  const reloadThreadTimerRef = useRef<number | null>(null)
  // Store manager callback, which will be called when state changes
  const reloadThreadFetchMessagesCallbackRef = useRef(() => {})
  const handleAutoSubmitRef = useRef(false)

  // Kick this off in the background so it doesn't block the rest of the chat from loading
  const checkForKnowledgeBases = useCallback(async () => {
    // This is used by the popover so if we don't need to render it, don't check for knowledge bases
    if (state.renderAttachKnowledgeBaseHerePopover) {
      await manager.fetchKnowledgeBases()
    }
  }, [manager, state.renderAttachKnowledgeBaseHerePopover])

  useEffect(() => {
    void checkForKnowledgeBases()
  }, [checkForKnowledgeBases])

  useEffect(() => {
    copilotLocalStorage.setSavedMessage(selectedThreadID, text)
  }, [selectedThreadID, text])

  useLayoutEffect(() => {
    let tries = 0

    function adjustHeight() {
      if (!textAreaRef.current || !textAreaPreviewContainerRef.current || !textareaPreviewRef.current) return

      tries++
      if (textAreaRef.current.scrollHeight === 0 && tries < 10) {
        // because this is (often) in a Portal, useLayoutEffect() can run before we're inserted in the DOM, and we are
        // thus unable to get a correct scrollHeight. in that case, let's try again in a bit
        // eslint-disable-next-line @eslint-react/web-api/no-leaked-timeout
        setTimeout(adjustHeight, 1)
      }

      textAreaRef.current.style.height = '0'
      const scrollHeight = textAreaRef.current.scrollHeight
      const containerHeight = Math.min(scrollHeight, MAX_HEIGHT)

      textareaPreviewRef.current.style.height = `${scrollHeight}px`
      textAreaRef.current.style.height = `${scrollHeight}px`
      textAreaPreviewContainerRef.current.style.height = `${containerHeight}px`
    }

    adjustHeight()
  }, [text, textAreaRef, textareaPreviewRef])

  const handleFocus = (e: React.FocusEvent<HTMLTextAreaElement>) => {
    // keep the current text focus
    if (e.currentTarget.selectionStart > 0) {
      return
    }
    // else set focus to end of text
    e.currentTarget.setSelectionRange(e.currentTarget.value.length, e.currentTarget.value.length)
  }

  const handleScroll = useCallback(() => {
    if (!textAreaRef?.current || !textareaPreviewRef?.current || !textAreaPreviewContainerRef?.current) return

    textareaPreviewRef.current.scrollTop = textAreaRef.current.scrollTop
    textareaPreviewRef.current.scrollLeft = textAreaRef.current.scrollLeft
  }, [textAreaRef])

  const sendableReferences = useMemo(
    () => state.currentReferences.filter(ref => !('isClientOnly' in ref) || !ref.isClientOnly),
    [state.currentReferences],
  )

  const handleSubmit = async (e?: FormEvent) => {
    setTypingHasStarted(false)

    // Clear all previously saved messages
    copilotLocalStorage.clearSavedUserMessage(selectedThreadID)
    copilotLocalStorage.clearSavedUserMessageOnError(selectedThreadID)

    if (state.defaultRecipient && !text.includes(`@${state.defaultRecipient}`)) {
      state.defaultRecipient = undefined
    }

    e?.preventDefault() // TODO: fix

    if (state.mode === 'assistive') {
      const ranSlashCommand = await executePotentialSlashCommand(text, state, manager)
      if (ranSlashCommand) {
        sendEvent('dotcom_chat.activate', {target: 'SLASH_COMMAND_EXECUTED', mode: state.mode, command: text})
        if (text.trim() === '/new') {
          copilotLocalStorage.setSavedMessageFast(selectedThreadID, null)
        }
        setText('')
        return
      }
    }

    if (!props.isLoading) {
      let messageToSubmit = text
      if (!messageToSubmit) {
        // get references from state
        const refs = sendableReferences
        const [inferred, newMessage] = manager.tryInferMessage(refs)
        if (!inferred || !newMessage) {
          return
        } else {
          messageToSubmit = newMessage
        }
      }
      setText('')
      await props.onSubmit?.(messageToSubmit)
    }
  }

  const handleSubmitToNewThread = useCallback(
    () => manager.sendMessageToNewThread(selectedThreadID, text, sendableReferences, state.context),
    [manager, selectedThreadID, state.context, sendableReferences, text],
  )

  useEffect(() => {
    const handlePrompt = async () => {
      const prompt = getPromptFromSearchParams(mode, pathname, searchParams)
      const updatedSearchParams = new URLSearchParams(searchParams)
      const queryModel = updatedSearchParams.get('model')
      const modelAvailable = !queryModel || queryModel === model.id

      if (prompt && modelAvailable && !handleAutoSubmitRef.current) {
        updatedSearchParams.delete('prompt')
        updatedSearchParams.delete('model')
        sendEvent('dotcom_chat.activate', {target: 'COPILOT_PROMPT_LOADED_FROM_URL', mode: 'immersive'})
        setSearchParams(updatedSearchParams, {replace: true})
        if (autoSubmit) {
          handleAutoSubmitRef.current = true
          // Wait for state update before submitting
          await Promise.resolve()
          await handleSubmit()
        }
      }
    }
    void handlePrompt()
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pathname, searchParams, setSearchParams, mode, autoSubmit, model])

  const handleChange = useCallback(
    (e: React.ChangeEvent<HTMLTextAreaElement>) => {
      setTypingHasStarted(true)

      if (!textAreaRef?.current) return

      setText((e.target as HTMLTextAreaElement).value)
      clearPastedFile?.()
      recallIndex.current = 0
      handleScroll()
    },
    [handleScroll, clearPastedFile, textAreaRef],
  )

  const handleStop = useCallback(async () => {
    await manager.stopStreaming()

    // Because the request didn't complete, the client only has the local/ephemeral copy of the streamed copilot response,
    // which doesn't have the real message id.
    // Re-fetch the messages from the server so that we have the final state with the correct message ids.
    if (selectedThreadID != null) {
      // Block new messages or retries from being sent while we're reloading the thread
      manager.startThreadReload()
      // Wait 6 seconds for server to complete the saving of the message
      // This matches server-side cancelation logic timing
      await new Promise<string>(timerDone => {
        reloadThreadTimerRef.current = setTimeout(() => timerDone(selectedThreadID), 6 * 1000) as unknown as number
      })
      reloadThreadFetchMessagesCallbackRef.current = await manager.fetchMessages(selectedThreadID, true, true)
    }
  }, [manager, selectedThreadID])

  // Once messages change in state, unblock registered fetchMessages await
  useEffect(() => {
    if (reloadThreadFetchMessagesCallbackRef.current) {
      reloadThreadFetchMessagesCallbackRef.current()
      reloadThreadFetchMessagesCallbackRef.current = () => {}
    }
  }, [state.messages])

  useEffect(() => {
    // Cleanup function to clear the reload timer on unmount or re-render
    return () => {
      // Return cleanup function - when component unmounts, stop the timer so that it doesn't try to reload the old thread
      if (reloadThreadTimerRef.current) {
        clearTimeout(reloadThreadTimerRef.current)
        reloadThreadTimerRef.current = null
      }
      // Also cancel the fetchMessages callbacks
      manager.cancelThreadReload()
      reloadThreadFetchMessagesCallbackRef.current = () => {}
    }
  }, [manager])

  return {
    typingHasStarted,
    textAreaRef,
    textareaPreviewRef,
    textAreaPreviewContainerRef,
    text,
    setText,
    handleSubmit,
    handleSubmitToNewThread,
    handleScroll,
    handleChange,
    handleStop,
    handleFocus,
  }
}

function getPromptFromSearchParams(mode: CopilotChatMode, pathname: string, searchParams: URLSearchParams) {
  if (mode === 'immersive' && (pathname === '/copilot' || pathname === '/copilot/')) {
    // Load prompt from URL if it exists
    const prompt = searchParams.get('prompt')
    if (prompt) {
      return prompt
    }
  }
  return undefined
}

import {sendEvent} from '@github-ui/hydro-analytics'
import {useIsPlatform} from '@github-ui/use-is-platform'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import type {FormEvent, RefObject} from 'react'
import type React from 'react'
import {useCallback, useEffect, useRef, useState} from 'react'
import {useLocation} from 'react-router-dom'

import {findAgentCorrespondents, isRepository} from '../utils/copilot-chat-helpers'
import {copilotLocalStorage} from '../utils/copilot-local-storage'
import {executePotentialSlashCommand} from '../utils/copilot-slash-commands'
import {useChatAutocomplete} from '../utils/CopilotChatAutocompleteContext'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import type {CopilotChatAgent, CustomCopilot} from './copilot-chat-types'
import {getSlugFromExtension} from './copilot-extensions-helpers'
import {copilotFeatureFlags} from './copilot-feature-flags'

const MAX_HEIGHT = 300

interface UseChatInputProps {
  textAreaRef?: RefObject<HTMLTextAreaElement>
  onSubmit?: (text: string) => Promise<void>
  onAbort?: () => void
  isLoading?: boolean
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
  /** handler for the keyDown event of the input textarea */
  handleKeyDown: (e: React.KeyboardEvent<HTMLTextAreaElement>) => Promise<void>
  /** handler for the onScroll event of the input textarea */
  handleScroll: () => void
  /** handler for the onChange event of the input textarea */
  handleChange: (e: React.ChangeEvent<HTMLTextAreaElement>) => void
  /** call to stop response streaming */
  handleStop: () => Promise<void>
  /** handler to move cursor to the end of prompt loaded from query params */
  handleFocus: (e: React.FocusEvent<HTMLTextAreaElement>) => void
  /** true if the option to reference knowledge bases should be shown */
  shouldShowKnowledge: boolean | undefined
}

/**
 * Does a bunch of stuff, too much really, to manage a chat input for a copilot chat.
 */
export function useChatInput(props: UseChatInputProps): UseChatInputReturn {
  const state = useChatState()
  const manager = useChatManager()
  const autocomplete = useChatAutocomplete()
  const {selectedThreadID} = state
  const savedUserMessage = copilotLocalStorage.getSavedMessage(selectedThreadID)
  const savedUserMessageOnError = copilotLocalStorage.getSavedUserMessageOnError(selectedThreadID)
  const [text, setText] = useState(savedUserMessageOnError ?? savedUserMessage ?? '')
  const [typingHasStarted, setTypingHasStarted] = useState(false)
  const isMac = useIsPlatform(['mac'])
  const internalRef = useRef<HTMLTextAreaElement>(null)
  const textAreaRef = props.textAreaRef || internalRef
  const textareaPreviewRef = useRef<HTMLDivElement>(null)
  const textAreaPreviewContainerRef = useRef<HTMLDivElement>(null)
  const userMessages = state.messages.filter(m => m.role === 'user')
  const recallIndex = useRef(0)
  const {search, pathname} = useLocation()

  const reloadThreadTimerRef = useRef<number | null>(null)
  // Store manager callback, which will be called when state changes
  const reloadThreadFetchMessagesCallbackRef = useRef(() => {})

  // Kick this off in the background so it doesn't block the rest of the chat from loading
  const checkForKnowledgeBases = useCallback(async () => {
    // This is used by the popover so if we don't need to render it, don't check for knowledge bases
    if (state.renderAttachKnowledgeBaseHerePopover) {
      await manager.fetchKnowledgeBases()
    }
  }, [manager, state.renderAttachKnowledgeBaseHerePopover])

  // Load prompt from URL if it exists
  useEffect(() => {
    if (state.mode !== 'immersive') return

    const urlSearchParams = new URLSearchParams(search)
    const prompt = urlSearchParams.get('prompt')

    if (prompt && (pathname === '/copilot' || pathname === '/copilot/')) {
      setText(prompt)
      sendEvent('dotcom_chat.activate', {target: 'COPILOT_PROMPT_LOADED_FROM_URL', mode: 'immersive'})
    } else {
      setText('')
    }
  }, [search, pathname, state.mode])

  useEffect(() => {
    void checkForKnowledgeBases()
  }, [checkForKnowledgeBases])

  // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
  const metaKey = (e: React.KeyboardEvent<HTMLTextAreaElement>) => (isMac ? e.metaKey : e.ctrlKey)

  // Preload file auto suggestions
  useEffect(() => {
    async function cacheAutocompletionData() {
      if (copilotFeatureFlags.topicsAsReferences) return

      const topic = state.currentTopic
      if (!topic || !isRepository(topic)) return

      if (state.currentTopic !== undefined) {
        await autocomplete.fetchAutocompleteSuggestions(topic, '')
      }
    }
    void cacheAutocompletionData()
  }, [autocomplete, state.currentTopic])

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
    e.currentTarget.setSelectionRange(e.currentTarget.value.length, e.currentTarget.value.length)
  }

  const handleKeyDown = async (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    setTypingHasStarted(true)
    // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    if (e.key === 'Enter' && !e.shiftKey && !e.ctrlKey && !e.altKey && !e.nativeEvent.isComposing) {
      e.preventDefault()
      await handleSubmit()
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    } else if (metaKey(e) && e.shiftKey && e.key === 's') {
      e.preventDefault()
      await handleSubmitToNewThread()
    } else if (
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      e.key === 'ArrowUp' &&
      textAreaRef.current &&
      (textAreaRef.current.value === '' || recallIndex.current > 0) &&
      textAreaRef.current.selectionStart === 0 &&
      userMessages?.length > recallIndex.current &&
      state.mode === 'assistive'
    ) {
      e.preventDefault()
      recallIndex.current++
      setText(userMessages[userMessages.length - recallIndex.current]!.content || '')
    } else if (
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      e.key === 'ArrowDown' &&
      recallIndex.current > 0 &&
      textAreaRef.current &&
      textAreaRef.current.selectionStart === textAreaRef.current.value.length &&
      state.mode === 'assistive'
    ) {
      e.preventDefault()
      recallIndex.current--
      if (recallIndex.current === 0) {
        setText('')
      } else {
        setText(userMessages[userMessages.length - recallIndex.current]!.content || '')
      }
    }
    handleScroll()
  }

  const handleScroll = useCallback(() => {
    if (!textAreaRef?.current || !textareaPreviewRef?.current || !textAreaPreviewContainerRef?.current) return

    textareaPreviewRef.current.scrollTop = textAreaRef.current.scrollTop
    textareaPreviewRef.current.scrollLeft = textAreaRef.current.scrollLeft
  }, [textAreaRef])

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
        const refs = state.currentReferences
        const [inferred, newMessage] = manager.tryInferMessage(refs)
        if (!inferred || !newMessage) {
          return
        } else {
          messageToSubmit = newMessage
        }
      }
      setText('')
      await props.onSubmit?.(messageToSubmit)
    } else {
      props.onAbort?.()
    }
  }

  const handleSubmitToNewThread = useCallback(
    () => manager.sendMessageToNewThread(selectedThreadID, text, state.currentReferences, state.context),
    [manager, selectedThreadID, state.context, state.currentReferences, text],
  )

  const handleChange = useCallback(
    (e: React.ChangeEvent<HTMLTextAreaElement>) => {
      setTypingHasStarted(true)

      if (!textAreaRef?.current) return

      setText((e.target as HTMLTextAreaElement).value)

      recallIndex.current = 0
      handleScroll()
    },
    [handleScroll, textAreaRef],
  )

  const handleStop = useCallback(async () => {
    await manager.stopStreaming()

    // Because the request didn't complete, the client only has the local/ephemeral copy of the streamed copilot response,
    // which doesn't have the real message id.
    // Re-fetch the messages from the server so that we have the final state with the correct message ids.
    if (selectedThreadID != null && copilotFeatureFlags.immersiveSubthreading) {
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
    handleKeyDown,
    handleScroll,
    handleChange,
    handleStop,
    handleFocus,
    shouldShowKnowledge:
      state.renderKnowledgeBases && ((state.currentTopic && isRepository(state.currentTopic)) || !state.currentTopic),
  }
}

interface UseTextareaPreviewProps {
  text: string
  textareaPreviewRef: RefObject<HTMLDivElement>
}

export function useTextareaPreview({text, textareaPreviewRef}: UseTextareaPreviewProps) {
  const manager = useChatManager()
  const state = useChatState()
  const [mention, setMention] = useState('')
  const [textAfterMention, setTextAfterMention] = useState('')
  const {agents, customCopilots, agentsPath, messages} = useChatState()

  useEffect(() => {
    if (!textareaPreviewRef.current) return
    const atMentions = text.match(/^@\S+/g)
    if (atMentions && atMentions.length > 0) {
      // Fetch the agents in case they weren't already loaded by the autocomplete.
      if (!agents) {
        if (agentsPath) {
          void manager.fetchAgents(agentsPath)
        }
      }

      const customCopilotsEnabled = copilotFeatureFlags.customCopilots
      if (customCopilotsEnabled && !customCopilots) {
        void manager.fetchCustomCopilots()
      }

      const extensions: Array<CopilotChatAgent | CustomCopilot> = []
      if (agents) {
        extensions.push(...agents)
      }
      if (customCopilots) {
        extensions.push(...customCopilots)
      }

      if (extensions.length === 0) {
        return
      }

      // if the user has previously communicated with an agent, that agent is the only agent allowed in the thread
      const previousExtensions = findAgentCorrespondents(messages)
      let filteredExtensions: Array<CopilotChatAgent | CustomCopilot>
      if (previousExtensions.length > 0) {
        const previousExtension = previousExtensions[0]!
        filteredExtensions = extensions.filter(extension => {
          const slug = getSlugFromExtension(extension)
          return slug === previousExtension.name
        })
      } else {
        filteredExtensions = extensions
      }

      // There should only be a single mention.
      const atMention = atMentions[0]

      // Check if the agents array contains the mention without the '@'
      const mentionSlug = atMention.substring(1)
      const matchingExtension = filteredExtensions.find(extension => {
        const slug = getSlugFromExtension(extension)
        return slug === mentionSlug
      })

      if (matchingExtension) {
        setMention(atMention)
        setTextAfterMention(text.replace(atMention, ''))
        return
      }
    }

    setMention('')
    setTextAfterMention('')
  }, [agents, agentsPath, customCopilots, manager, messages, state.mode, text, textareaPreviewRef])

  return {
    mention,
    textAfterMention,
  }
}

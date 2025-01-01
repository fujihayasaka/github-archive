import {sendEvent} from '@github-ui/hydro-analytics'
import {useIsPlatform} from '@github-ui/use-is-platform'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import type {FormEvent, RefObject} from 'react'
import type React from 'react'
import {useCallback, useEffect, useRef, useState} from 'react'

import {findAgentCorrespondents, isRepository} from '../utils/copilot-chat-helpers'
import {copilotLocalStorage} from '../utils/copilot-local-storage'
import {executePotentialSlashCommand} from '../utils/copilot-slash-commands'
import {useChatAutocomplete} from '../utils/CopilotChatAutocompleteContext'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import type {CopilotChatAgent} from './copilot-chat-types'

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
  /** handler for the keyDown event of the input textarea */
  handleKeyDown: (e: React.KeyboardEvent<HTMLTextAreaElement>) => Promise<void>
  /** handler for the onScroll event of the input textarea */
  handleScroll: () => void
  /** handler for the onChange event of the input textarea */
  handleChange: (e: React.ChangeEvent<HTMLTextAreaElement>) => void
  /** call to stop response streaming */
  handleStop: () => Promise<void>
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
  const [text, setText] = useState(savedUserMessage ?? '')
  const [typingHasStarted, setTypingHasStarted] = useState(false)
  const isMac = useIsPlatform(['mac'])
  const internalRef = useRef<HTMLTextAreaElement>(null)
  const textAreaRef = props.textAreaRef || internalRef
  const textareaPreviewRef = useRef<HTMLDivElement>(null)
  const textAreaPreviewContainerRef = useRef<HTMLDivElement>(null)
  const userMessages = state.messages.filter(m => m.role === 'user')
  const recallIndex = useRef(0)

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

  // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
  const metaKey = (e: React.KeyboardEvent<HTMLTextAreaElement>) => (isMac ? e.metaKey : e.ctrlKey)

  // Preload file auto suggestions
  useEffect(() => {
    async function cacheAutocompletionData() {
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

  const handleKeyDown = async (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    setTypingHasStarted(true)
    // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    if (e.key === 'Enter' && !e.shiftKey && !e.ctrlKey && !e.altKey && !e.nativeEvent.isComposing) {
      e.preventDefault()
      await handleSubmit()
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    } else if (metaKey(e) && e.shiftKey && e.key === 's') {
      e.preventDefault()
      await manager.sendMessageToNewThread(selectedThreadID, text, state.currentReferences, state.context)
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
      if (!text) return
      setText('')
      await props.onSubmit?.(text)
    } else {
      props.onAbort?.()
    }
  }

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

  const handleStop = useCallback(() => manager.stopStreaming(), [manager])

  return {
    typingHasStarted,
    textAreaRef,
    textareaPreviewRef,
    textAreaPreviewContainerRef,
    text,
    setText,
    handleSubmit,
    handleKeyDown,
    handleScroll,
    handleChange,
    handleStop,
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
  const {agents, agentsPath, messages} = useChatState()

  useEffect(() => {
    if (!textareaPreviewRef.current) return
    const atMentions = text.match(/^@\S+/g)
    if (atMentions && atMentions.length > 0) {
      // Fetch the agents in case they weren't already loaded by the autocomplete.
      if (!agents) {
        if (agentsPath) {
          void manager.fetchAgents(agentsPath)
        }
        return
      }

      if (agents.length === 0) {
        return
      }

      sendEvent('dotcom_chat.activate', {target: 'AGENT_MENU_TRIGGERED', mode: state.mode})

      // if the user has previously communicated with an agent, that agent is the only agent allowed in the thread
      const previousAgents = findAgentCorrespondents(messages)
      let filteredAgents: CopilotChatAgent[]
      if (previousAgents.length > 0) {
        const previousAgent = previousAgents[0]!
        filteredAgents = agents.filter(agent => agent.slug === previousAgent.name)
      } else {
        filteredAgents = agents
      }

      // There should only be a single mention.
      const atMention = atMentions[0]

      // Check if the agents array contains the mention without the '@'
      const mentionSlug = atMention.substring(1)
      const matchingAgent = filteredAgents.find(agent => agent.slug === mentionSlug)
      if (matchingAgent) {
        setMention(atMention)
        setTextAfterMention(text.replace(atMention, ''))
        return
      }
    }

    setMention('')
    setTextAfterMention('')
  }, [agents, agentsPath, manager, messages, state.mode, text, textareaPreviewRef])

  return {
    mention,
    textAfterMention,
  }
}

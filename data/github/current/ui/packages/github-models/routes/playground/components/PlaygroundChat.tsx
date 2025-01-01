import {debounce} from '@github/mini-throttle'
import {modelPlaygroundPath, type Repository} from '@github-ui/paths'
import {PlaygroundChatInput} from './PlaygroundChatInput'
import {PlaygroundChatMessage} from './PlaygroundChatMessage'
import {useEffect, useCallback, useRef, useState, useMemo} from 'react'
import {Panel} from '../../../utils/playground-manager'
import {usePlaygroundManager} from '../../../contexts/PlaygroundManagerContext'
import {usePlaygroundState} from '../../../contexts/PlaygroundStateContext'
import {IconButton, SegmentedControl} from '@primer/react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'

import {
  getSavedPlaygroundMessages,
  setPlaygroundLocalStorageMessages,
  type ModelPersistentUIState,
  type StoredChatMessages,
} from '../../../utils/playground-local-storage'
import {PlaygroundContentOption, playgroundContentSuffixes} from './types'
import type {ModelState, PlaygroundMessage, GettingStartedPayload} from '../../../types'
import {SidebarSelectionOptions} from '../../../types'
import {ModelLegalTerms} from '../../../components/ModelLegalTerms'
import {SidebarCollapseIcon, SlidersIcon, TrashIcon} from '@primer/octicons-react'
import PlaygroundChatEmptyState from './PlaygroundChatEmptyState'
import {useNavigate, useSearchParams} from '@github-ui/use-navigate'
import {useLocation} from 'react-router-dom'
import {PlaygroundCodeSnippet} from './PlaygroundCodeSnippet'
import {PlaygroundJSON} from './PlaygroundJSON'
import {textFromMessageContent} from '../../../utils/message-content-helper'
import {Toolbar} from './Toolbar'
import {useMessageHistory} from './MessageHistoryContext'
import {supportImageWithoutText} from '../../../utils/image-validation'
import {PlaygroundToolCallMessage} from './PlaygroundToolCallMessage'
import {ComparisonModeMenu} from './ComparisonModeMenu'
import {PlaygroundTokenUsageWidget} from './PlaygroundTokenUsageWidget'
import {AttachmentsProvider} from '@github-ui/attachments'
import {useModelClient} from '../contexts/ModelClientContext'
import {getDefaultTokenUsage} from '../../../utils/model-usage'
import {announce} from '@github-ui/aria-live'
import {MaxTokensBanner} from './MaxTokensBanner'
import {MAX_ATTACHMENT_COUNT} from './attachments/constants'
import {useUser} from '@github-ui/use-user'
import {PlaygroundChatMessageHeader} from './PlaygroundChatMessageHeader'
import {useLowRateLimitTierModels} from '../hooks/use-query-models'
import styles from './PlaygroundChat.module.css'
import {clsx} from 'clsx'
import {useFilteredModels} from '@github-ui/github-models-repo/UseFilteredModels'

function assertValidPlaygroundContentOption(
  value: number,
  onComparisonMode: boolean = false,
): asserts value is PlaygroundContentOption {
  if (onComparisonMode) {
    if (value === PlaygroundContentOption.CHAT || value === PlaygroundContentOption.PARAMETERS) return
    throw new Error(`Invalid Option "${value}".`)
  }
  if (new Set<number>(Object.values(PlaygroundContentOption)).has(value)) return
  throw new Error(`Invalid GettingStartedContentOption "${value}".`)
}

export function PlaygroundChat({
  model,
  position,
  showSidebar,
  onComparisonMode,
  handleSetSidebarTab,
  handleShowSidebar,
  stopStreamingMessages,
  uiState,
  handleSelectLanguage,
  handleSelectSDK,
  repository,
}: {
  model: ModelState
  position: number
  showSidebar: boolean
  onComparisonMode: boolean
  handleSetSidebarTab: (newTab: SidebarSelectionOptions) => void
  handleShowSidebar: (value: boolean) => void
  stopStreamingMessages: () => void
  uiState: ModelPersistentUIState
  handleSelectLanguage: (language: string) => void
  handleSelectSDK: (sdk: string) => void
  repository?: Repository
}) {
  const state = usePlaygroundState()
  const {models, syncInputs} = state
  const {messages, isLoading, catalogData, parametersHasChanges, modelInputSchema, gettingStarted} = model
  const lastIndex = messages.length - 1
  const messagesContainerRef = useRef<HTMLDivElement>(null)
  const scrolledToBottomRef = useRef(true)
  const manager = usePlaygroundManager()
  const {setHistory} = useMessageHistory()
  const modelClient = useModelClient()
  const {restrictedModels} = useRoutePayload<GettingStartedPayload>()

  const {availableModels: repoModels} = useFilteredModels(
    repository?.ownerLogin || '',
    repository?.name || '',
    restrictedModels,
  )
  const location = useLocation()
  const navigate = useNavigate()
  const [searchParams, setSearchParams] = useSearchParams()
  const showMessages =
    messages.length > 0 || searchParams.has('p') || searchParams.has('mp') || searchParams.has('prompt')

  const maxAttachmentCount = Math.min(
    MAX_ATTACHMENT_COUNT,
    ...models.map(modelState => modelState.modelInputSchema?.capabilities?.chat?.imagesPerTurn || MAX_ATTACHMENT_COUNT),
  )

  const chatInputRef = useRef<HTMLTextAreaElement | null>(null)
  const [toolbarContent, setToolbarContent] = useState<React.ReactNode | null>(null)
  const [fullWidthToolbarContent, setFullWidthToolbarContent] = useState<React.ReactNode | null>(null)

  const [selectedOption, setSelectedOption] = useState<PlaygroundContentOption>(() => {
    if (onComparisonMode) return PlaygroundContentOption.CHAT

    const finalPathComponent = location.pathname.split('/').pop()?.toLowerCase()

    switch (finalPathComponent) {
      case 'code':
        return PlaygroundContentOption.CODE
      case 'json':
        return PlaygroundContentOption.JSON
      default:
        return PlaygroundContentOption.CHAT
    }
  })

  useEffect(() => {
    if (onComparisonMode) return
    if (!onComparisonMode && selectedOption === PlaygroundContentOption.PARAMETERS) {
      // When the browser is resized to a mobile width
      setSelectedOption(PlaygroundContentOption.CHAT)
    }
  }, [onComparisonMode, selectedOption])

  const scrollToBottom = useCallback(() => {
    const forceScroll = false // Might be needed later

    function isScrollable(element: HTMLElement): boolean {
      if (!element.scrollTo) return false // This happens in the jest tests on CI
      return window.getComputedStyle(element).overflowY === 'auto'
    }

    if (!messagesContainerRef.current) return // This is not expected
    if (!scrolledToBottomRef.current && !forceScroll) return // The user has scrolled up, let's not scroll them back down

    // Depending on the screen size and the mode, we might either have a scroll
    // container around the messages, or we might use the window scroll.
    if (isScrollable(messagesContainerRef.current)) {
      messagesContainerRef.current.scrollTo(0, messagesContainerRef.current.scrollHeight)
    } else {
      window.scrollTo(0, document.body.scrollHeight)
    }
  }, [])

  useEffect(() => {
    if (onComparisonMode) return
    const savedMessages = getSavedPlaygroundMessages(repository)
    if (savedMessages && savedMessages.modelName === catalogData.name) {
      setHistory({
        model: savedMessages.modelName ?? '',
        messages: savedMessages.messages ?? [],
        tokenUsage: savedMessages.tokenUsage ?? getDefaultTokenUsage(),
      })
    }
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [catalogData.name, onComparisonMode, setHistory])

  useEffect(() => {
    requestAnimationFrame(scrollToBottom)
  }, [messages, scrollToBottom])

  useEffect(() => {
    if (isLoading) {
      announce(`${catalogData.friendly_name} is responding...`)
    }
  }, [isLoading, catalogData.friendly_name])

  const handleScroll = useCallback(() => {
    if (!messagesContainerRef.current) return
    // This calculation can be finnicky with fractional pixels. If we're within 1px of the bottom, we are close enough.
    const {scrollHeight, scrollTop, clientHeight} = messagesContainerRef.current
    scrolledToBottomRef.current = Math.abs(scrollHeight - scrollTop - clientHeight) <= 1
  }, [])

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLDivElement>) => {
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (['ArrowUp', 'ArrowDown', 'PageUp', 'PageDown', 'Home', 'End'].includes(e.key)) {
        handleScroll()
      }
    },
    [handleScroll],
  )

  const debounceSetPlaygroundLocalStorageMessages = useMemo(
    () =>
      debounce((newMessages: StoredChatMessages) => {
        setPlaygroundLocalStorageMessages(newMessages, repository)
      }, 200),
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [],
  )

  useEffect(() => {
    if (position !== Panel.Main) return
    if (messages.length > 0) {
      const chatMessages = {
        modelName: catalogData.name,
        messages,
        tokenUsage: model.tokenUsage,
      }
      debounceSetPlaygroundLocalStorageMessages(chatMessages)
    }
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [messages, debounceSetPlaygroundLocalStorageMessages, catalogData.name, position])

  const handleClearHistory = useCallback(() => {
    stopStreamingMessages()
    manager.resetHistory(position, repository)
    searchParams.delete('p')
    searchParams.delete('mp')
    searchParams.delete('prompt')
    setSearchParams(searchParams)
    setHistory({model: '', messages: [], tokenUsage: getDefaultTokenUsage()})
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [manager, position, searchParams, setHistory, setSearchParams, stopStreamingMessages])

  const handleOptionChange = (option: number) => {
    if (option === selectedOption) return
    assertValidPlaygroundContentOption(option)
    setSelectedOption(option)

    // We only want to update the URL when the user is on a single model view
    if (onComparisonMode || option === PlaygroundContentOption.PARAMETERS) return

    const playgroundUrl = modelPlaygroundPath(catalogData)
    const suffix = playgroundContentSuffixes[option]

    navigate({
      pathname: `${playgroundUrl}${suffix}`,
      search: searchParams.toString(),
    })
  }

  const sendMessage = useCallback(
    (index: number, modelState: ModelState, text: string, attachments: string[]) => {
      manager.sendMessage(index, modelState, modelClient, text, attachments)
    },
    [manager, modelClient],
  )

  const sendMessageSynced = (text: string, attachments: string[] = []) => {
    for (const [index, m] of models.entries()) {
      if (syncInputs || position === index) {
        sendMessage(index, m, text, attachments)
      }
    }
  }

  const handleRegenerate = useCallback(
    (index: number, suggestion: string = '') => {
      if (index > messages.length) return
      const isLastResponse = index + 1 === messages.length
      if (!isLastResponse) return
      const messageContent = messages && messages[index - 1]?.message
      if (!messageContent) return
      let text = textFromMessageContent(messageContent)
      if (suggestion) {
        text = `${text}\n${suggestion}`
      }
      if (!text && !supportImageWithoutText(model.catalogData.name)) return
      let attachments = [] as string[]
      if (typeof messageContent === 'object') {
        attachments = messageContent.filter(m => m.type === 'image_url').map(m => m.image_url.url)
      }

      // Remove the latest message and response
      const filteredMessages = messages.slice(0, -2)
      const newModelState = {...model, messages: filteredMessages}
      sendMessage(position, newModelState, text, attachments)
    },
    [messages, model, position, sendMessage],
  )

  const handleEdit = useCallback(
    (index: number) => {
      if (onComparisonMode) return
      const messageContent = messages && messages[index - 1]?.message
      if (!messageContent) return
      const text = textFromMessageContent(messageContent)
      const filteredMessages = messages.slice(0, index - 1)
      const {lastMessageOutputTokens, totalOutputTokens} = model.tokenUsage
      const newTokenUsage = {
        ...model.tokenUsage,
        lastMessageOutputTokens: 0,
        totalOutputTokens: totalOutputTokens - lastMessageOutputTokens,
      }
      const newModelState = {...model, chatInput: text, messages: filteredMessages, tokenUsage: newTokenUsage}
      manager.setModelState(position, newModelState)
      requestAnimationFrame(() => chatInputRef.current?.focus())
    },
    [messages, model, position, manager, onComparisonMode],
  )

  const isToolCallMessage = useCallback((message: PlaygroundMessage) => {
    return (
      message.role === 'assistant' &&
      Array.isArray(message.message) &&
      message.message.length > 0 &&
      message.message[0]!.type === 'tool_calls'
    )
  }, [])

  const showMessageHeader = (message: PlaygroundMessage, index: number) => {
    // we don't need another message header if the error occurs right after a partially-streamed assistant message
    const prevMessage = messages[index - 1]
    const isPrevMessageFromAssistant = prevMessage?.role === 'assistant'
    return !(isPrevMessageFromAssistant && message.role === 'error')
  }

  const {currentUser} = useUser()

  const handleImproveSuggestion = useCallback(
    (index: number, suggestion: string) => {
      handleRegenerate(index, suggestion)
    },
    [handleRegenerate],
  )

  const {data: lowRateLimitTierModels} = useLowRateLimitTierModels(
    catalogData.publisher,
    onComparisonMode,
    catalogData.rate_limit_tier,
  )

  const allowedLowRateLimitTierModels = useMemo(() => {
    if (!repository) {
      return lowRateLimitTierModels
    }
    return lowRateLimitTierModels.filter(m => repoModels.find(repoModel => repoModel.name === m.name))
  }, [repository, lowRateLimitTierModels, repoModels])

  const renderOption = (option: PlaygroundContentOption) => {
    switch (option) {
      case PlaygroundContentOption.CHAT:
        return (
          <div className="pl-3 pb-2 overflow-auto flex-1 d-flex flex-column">
            <div
              className="flex-1 d-flex flex-column flex-justify-between pr-3 overflow-auto mb-3"
              ref={messagesContainerRef}
              onWheel={handleScroll}
              onKeyDown={handleKeyDown}
              role="textbox"
              aria-label="Playground chat"
              tabIndex={0}
            >
              <div className="flex-1 position-relative py-3">
                {showMessages ? (
                  <div className="position-absolute width-full">
                    {messages.map((message, index) => {
                      return isToolCallMessage(message) ? (
                        <PlaygroundToolCallMessage
                          message={message}
                          key={`${message.timestamp}-${JSON.stringify(message.message)}`}
                        />
                      ) : (
                        // Each message doesn't have a unique identifier
                        // eslint-disable-next-line @eslint-react/no-array-index-key
                        <div key={`${message.role}-${index}`}>
                          {showMessageHeader(message, index) && (
                            <PlaygroundChatMessageHeader
                              message={message}
                              model={model.catalogData}
                              currentUser={currentUser}
                              isLoading={index === lastIndex && isLoading}
                            />
                          )}
                          <PlaygroundChatMessage
                            model={model}
                            message={message}
                            index={index}
                            isLoading={index === lastIndex && isLoading}
                            isError={message.role === 'error'}
                            lastIndex={index === lastIndex}
                            handleRegenerate={handleRegenerate}
                            handleEdit={onComparisonMode ? undefined : handleEdit}
                            handleClearHistory={handleClearHistory}
                            handleImproveSuggestion={handleImproveSuggestion}
                            lowRateLimitTierModels={allowedLowRateLimitTierModels}
                          />
                        </div>
                      )
                    })}
                    <MaxTokensBanner modelState={model} />
                  </div>
                ) : (
                  <PlaygroundChatEmptyState model={model} submitMessage={sendMessageSynced} />
                )}
              </div>
            </div>
            <PlaygroundChatInput
              ref={chatInputRef}
              model={model}
              position={position}
              sendMessage={sendMessageSynced}
              stopStreamingMessages={stopStreamingMessages}
            />
            {!onComparisonMode && (
              <div className="pt-3 pb-2 d-flex flex-justify-center pr-3">
                <ModelLegalTerms modelName={catalogData.name} />
              </div>
            )}
          </div>
        )
      case PlaygroundContentOption.CODE: {
        return <PlaygroundCodeSnippet model={model} uiState={uiState} />
      }
      case PlaygroundContentOption.JSON: {
        return (
          <PlaygroundJSON
            setFullWidthToolbarContent={setFullWidthToolbarContent}
            setToolbarContent={setToolbarContent}
            model={model}
            position={position}
            stopStreamingMessages={stopStreamingMessages}
            sendMessage={sendMessageSynced}
          />
        )
      }
      case PlaygroundContentOption.PARAMETERS: {
        return <ComparisonModeMenu modelState={model} position={position} repository={repository} />
      }
    }
  }
  return (
    <div className={styles.container}>
      {fullWidthToolbarContent ? (
        <div className={clsx(styles.header, styles.edit)}>{fullWidthToolbarContent}</div>
      ) : (
        <div className={clsx(styles.header)}>
          <div className={`d-flex ${!onComparisonMode && 'gap-2'}`}>
            <div className="hide-md hide-sm">
              {!showSidebar && !onComparisonMode && (
                <IconButton
                  icon={SidebarCollapseIcon}
                  size="small"
                  aria-label="Show parameters setting"
                  onClick={() => handleShowSidebar(true)}
                />
              )}
            </div>

            {(!repository || onComparisonMode) && (
              <SegmentedControl
                aria-label={
                  selectedOption === PlaygroundContentOption.CHAT ? 'Show playground chat' : 'Show code sample'
                }
                size="small"
                onChange={handleOptionChange}
              >
                <SegmentedControl.Button selected={selectedOption === PlaygroundContentOption.CHAT}>
                  Chat
                </SegmentedControl.Button>
                <SegmentedControl.Button
                  className={onComparisonMode ? 'd-none' : ''}
                  selected={selectedOption === PlaygroundContentOption.CODE}
                >
                  Code
                </SegmentedControl.Button>
                <SegmentedControl.Button
                  className={onComparisonMode ? 'd-none' : ''}
                  selected={selectedOption === PlaygroundContentOption.JSON}
                >
                  Raw
                </SegmentedControl.Button>
                {onComparisonMode && (
                  <SegmentedControl.Button selected={selectedOption === PlaygroundContentOption.PARAMETERS}>
                    Parameters
                  </SegmentedControl.Button>
                )}
              </SegmentedControl>
            )}
          </div>
          <div className="d-flex gap-2">
            <PlaygroundTokenUsageWidget modelState={model} position={position} />
            <Toolbar
              onComparisonMode={onComparisonMode}
              modelState={model}
              option={selectedOption}
              position={position}
              uiState={uiState}
              handleSelectLanguage={handleSelectLanguage}
              handleSelectSDK={handleSelectSDK}
              handleClearHistory={handleClearHistory}
            >
              {toolbarContent}
            </Toolbar>
            {onComparisonMode && selectedOption === PlaygroundContentOption.PARAMETERS ? (
              <IconButton
                size="small"
                icon={TrashIcon}
                as="button"
                disabled={!parametersHasChanges}
                aria-label="Reset to default inputs"
                onClick={() => {
                  const currentModelDetails = {
                    catalogData,
                    modelInputSchema,
                    gettingStarted,
                  }

                  for (const [index] of models.entries()) {
                    if (index === position || syncInputs) {
                      manager.resetParamsAndSystemPrompt(index, currentModelDetails)
                    }
                  }
                }}
              />
            ) : (
              <div className="hide-lg hide-xl">
                <IconButton
                  icon={SlidersIcon}
                  size="small"
                  aria-label="Show parameters setting"
                  onClick={() => handleSetSidebarTab(SidebarSelectionOptions.PARAMETERS)}
                />
              </div>
            )}
          </div>
        </div>
      )}

      <AttachmentsProvider subscribed={syncInputs} attachLimit={maxAttachmentCount}>
        {renderOption(selectedOption)}
      </AttachmentsProvider>
    </div>
  )
}

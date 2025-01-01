import {debounce} from '@github/mini-throttle'
import {PlaygroundChatInput} from './PlaygroundChatInput'
import {PlaygroundChatMessage} from './PlaygroundChatMessage'
import {useEffect, useCallback, useRef, useState, useMemo} from 'react'
import {Panel, usePlaygroundManager} from '../../../utils/playground-manager'
import {usePlaygroundState} from '../../../contexts/PlaygroundStateContext'
import {Box, IconButton, SegmentedControl} from '@primer/react'

import {
  getSavedPlaygroundMessages,
  setPlaygroundLocalStorageMessages,
  type StoredChatMessages,
} from '../../../utils/playground-local-storage'
import {PlaygroundContentOption, playgroundContentSuffixes} from './types'
import type {ModelState, PlaygroundMessage} from '../../../types'
import {SidebarSelectionOptions} from '../../../types'
import {ModelLegalTerms} from './GettingStartedDialog/ModelLegalTerms'
import {SidebarExpandIcon, SlidersIcon} from '@primer/octicons-react'
import PlaygroundChatEmptyState from './PlaygroundChatEmptyState'
import {useNavigate, useSearchParams} from '@github-ui/use-navigate'
import {useLocation} from 'react-router-dom'
import {ModelUrlHelper} from '../../../utils/model-url-helper'
import {PlaygroundCodeSnippet} from './PlaygroundCodeSnippet'
import {PlaygroundJSON} from './PlaygroundJSON'
import {textFromMessageContent} from '../../../utils/message-content-helper'
import {Toolbar} from './Toolbar'
import {useMessageHistory} from './MessageHistoryContext'
import {supportImageWithoutText} from '../../../utils/image-validation'
import {PlaygroundToolCallMessage} from './PlaygroundToolCallMessage'
import type {AzureModelClient} from '../../../utils/azure-model-client'
import {ComparisonModeMenu} from './ComparisonModeMenu'
import {AttachmentsProvider} from './attachments/AttachmentsProvider'

export function PlaygroundChat({
  model,
  position,
  modelClient,
  showSidebar,
  onComparisonMode,
  handleSetSidebarTab,
  handleShowSidebar,
  stopStreamingMessages,
}: {
  model: ModelState
  position: number
  modelClient: AzureModelClient
  showSidebar: boolean
  onComparisonMode: boolean
  handleSetSidebarTab: (newTab: SidebarSelectionOptions) => void
  handleShowSidebar: (value: boolean) => void
  stopStreamingMessages: () => void
}) {
  const {models, syncInputs} = usePlaygroundState()
  const {messages, isLoading, catalogData} = model
  const lastIndex = messages.length - 1
  const messagesContainerRef = useRef<HTMLDivElement>(null)
  const scrolledToBottomRef = useRef(true)
  const manager = usePlaygroundManager()
  const {setHistory} = useMessageHistory()

  const location = useLocation()
  const navigate = useNavigate()
  const [searchParams, setSearchParams] = useSearchParams()
  const showMessages = messages.length > 0 || searchParams.has('p')

  const [toolbarContent, setToolbarContent] = useState<React.ReactNode | null>(null)
  const [fullWidthToolbarContent, setFullWidthToolbarContent] = useState<React.ReactNode | null>(null)

  const [selectedOption, setSelectedOption] = useState<number>(() => {
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
    const savedMessages = getSavedPlaygroundMessages()
    const chatHistory = savedMessages && savedMessages.modelName === catalogData.name ? savedMessages.messages : []
    setHistory(chatHistory)
  }, [catalogData.name, onComparisonMode, setHistory])

  useEffect(() => {
    scrollToBottom()
  }, [messages, scrollToBottom])

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
        setPlaygroundLocalStorageMessages(newMessages)
      }, 200),
    [],
  )

  useEffect(() => {
    if (position !== Panel.Main) return
    if (messages.length > 0) {
      const chatMessages = {
        modelName: catalogData.name,
        messages,
      }
      debounceSetPlaygroundLocalStorageMessages(chatMessages)
    }
  }, [messages, debounceSetPlaygroundLocalStorageMessages, catalogData.name, position])

  const handleClearHistory = () => {
    stopStreamingMessages()
    manager.resetHistory(position)
    searchParams.delete('p')
    setSearchParams(searchParams)
    setHistory([])
  }

  const handleOptionChange = (option: PlaygroundContentOption) => {
    if (option === selectedOption) return
    setSelectedOption(option)

    // We only want to update the URL for the main model
    if (position !== Panel.Main) return

    const playgroundUrl = ModelUrlHelper.playgroundUrl(catalogData)
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

  const smallSizeForSegmentControl = {
    height: '28px',
    fontSize: 1,
  }

  const handleRegenerate = useCallback(
    (index: number) => {
      if (index > messages.length) return
      const isLastResponse = index + 1 === messages.length
      if (!isLastResponse) return
      const messageContent = messages && messages[index - 1]?.message
      if (!messageContent) return
      const text = textFromMessageContent(messageContent)
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

  const isToolCallMessage = useCallback((message: PlaygroundMessage) => {
    return (
      message.role === 'assistant' &&
      Array.isArray(message.message) &&
      message.message.length > 0 &&
      message.message[0]!.type === 'tool_calls'
    )
  }, [])

  const renderOption = (option: PlaygroundContentOption) => {
    switch (option) {
      case PlaygroundContentOption.CHAT:
        return (
          <div className="pl-3 pb-2 overflow-auto flex-1 d-flex flex-column">
            <div
              className="flex-1 d-flex flex-column flex-justify-between pr-3 overflow-auto"
              ref={messagesContainerRef}
              onWheel={handleScroll}
              onKeyDown={handleKeyDown}
              role="textbox"
              aria-label="Playground chat"
              tabIndex={0}
            >
              <div className="flex-1 position-relative pt-3">
                {showMessages ? (
                  <div className="position-absolute">
                    {messages.map((message, index) =>
                      isToolCallMessage(message) ? (
                        <PlaygroundToolCallMessage message={message} key={`${message.timestamp}-${message.message}`} />
                      ) : (
                        <PlaygroundChatMessage
                          model={model}
                          message={message}
                          index={index}
                          key={`${message.timestamp}-${message.message}`}
                          isLoading={index === lastIndex && isLoading}
                          isError={message.role === 'error'}
                          lastIndex={index === lastIndex}
                          handleRegenerate={handleRegenerate}
                          handleClearHistory={handleClearHistory}
                        />
                      ),
                    )}
                  </div>
                ) : (
                  <PlaygroundChatEmptyState model={model} submitMessage={sendMessageSynced} />
                )}
              </div>
            </div>
            <PlaygroundChatInput
              model={model}
              position={position}
              sendMessage={sendMessageSynced}
              stopStreamingMessages={stopStreamingMessages}
            />
            <div className="pt-3 pb-2 d-flex flex-justify-center pr-3">
              <ModelLegalTerms modelName={catalogData.name} />
            </div>
          </div>
        )
      case PlaygroundContentOption.CODE: {
        return <PlaygroundCodeSnippet model={model} />
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
    }
  }

  return (
    <div className="flex-1 d-flex flex-column min-width-0 height-full">
      {fullWidthToolbarContent ? (
        <Box
          sx={{
            backgroundColor: 'canvas.subtle',
            gap: 2,
            p: 2,
            display: 'flex',
            justifyContent: 'space-between',
            borderBottomColor: 'border.default',
            borderBottomWidth: 1,
            borderBottomStyle: 'solid',
          }}
        >
          {fullWidthToolbarContent}
        </Box>
      ) : (
        <Box
          sx={{
            backgroundColor: 'canvas.subtle',
            p: 2,
            display: 'flex',
            justifyContent: 'space-between',
            borderBottomColor: 'border.default',
            borderBottomWidth: 1,
            borderBottomStyle: 'solid',
          }}
        >
          <SegmentedControl
            aria-label={selectedOption === PlaygroundContentOption.CHAT ? 'Show playground chat' : 'Show code sample'}
            sx={smallSizeForSegmentControl}
            size="small"
            onChange={handleOptionChange}
          >
            <SegmentedControl.Button
              sx={smallSizeForSegmentControl}
              selected={selectedOption === PlaygroundContentOption.CHAT}
            >
              Chat
            </SegmentedControl.Button>
            <SegmentedControl.Button
              sx={smallSizeForSegmentControl}
              selected={selectedOption === PlaygroundContentOption.CODE}
            >
              Code
            </SegmentedControl.Button>
            <SegmentedControl.Button
              sx={smallSizeForSegmentControl}
              selected={selectedOption === PlaygroundContentOption.JSON}
            >
              Raw
            </SegmentedControl.Button>
          </SegmentedControl>

          <Box sx={{display: 'flex', gap: 2}}>
            <Toolbar
              onComparisonMode={onComparisonMode}
              modelState={model}
              option={selectedOption}
              position={position}
              stopStreamingMessages={stopStreamingMessages}
            >
              {toolbarContent}
            </Toolbar>
            {onComparisonMode ? (
              <ComparisonModeMenu modelState={model} position={position} />
            ) : (
              <>
                {!showSidebar && (
                  <IconButton
                    icon={SidebarExpandIcon}
                    size="small"
                    aria-label="Show parameters setting"
                    onClick={() => handleShowSidebar(true)}
                  />
                )}
                <div className="hide-lg hide-xl">
                  <IconButton
                    icon={SlidersIcon}
                    size="small"
                    aria-label="Show parameters setting"
                    onClick={() => handleSetSidebarTab(SidebarSelectionOptions.PARAMETERS)}
                  />
                </div>
              </>
            )}
          </Box>
        </Box>
      )}

      <AttachmentsProvider>{renderOption(selectedOption)}</AttachmentsProvider>
    </div>
  )
}

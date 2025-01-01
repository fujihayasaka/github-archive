import type {CopilotChatRepo, Docset} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {copilotLocalStorage} from '@github-ui/copilot-chat/utils/copilot-local-storage'
import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/utils/CopilotChatManagerContext'
import {clsx} from 'clsx'
import {useCallback, useEffect, useRef, useState} from 'react'

import {useContentPreview} from '../hooks/use-content-preview'
import {ChatInput} from './ChatInput'
import {ContentPreview} from './ContentPreview/ContentPreview'
import {Header} from './Header'
import {ImmersiveChat} from './ImmersiveChat'
import classes from './Layout.module.css'
import {Sidebar} from './Sidebar'
import {TopicIndicator} from './TopicIndicator'

export function Layout() {
  const state = useChatState()
  const {currentReferences, context, scrollToTop, selectedThreadID} = state
  const manager = useChatManager()

  const thread = manager.getSelectedThread(state)
  const scrollToTopRef = useRef(scrollToTop)
  const chatTextAreaRef = useRef<HTMLTextAreaElement>(null)
  const textAreaRef = chatTextAreaRef
  const currentTopic = useRef<CopilotChatRepo | Docset | undefined>(state.currentTopic)
  const [previewPaneOpen, setPreviewPaneOpen] = useState(false)
  const {previewItems: previewPaneItems, clearPreviewItems} = useContentPreview()

  useEffect(() => {
    setPreviewPaneOpen(previewPaneItems.length > 0)
  }, [previewPaneItems.length])

  useEffect(() => {
    currentTopic.current = state.currentTopic
  }, [state.currentTopic])

  const handleUserSubmit = useCallback(
    async (content: string) => {
      scrollToTopRef.current = false
      const trimmedContent = content.trim()
      if (trimmedContent === '') return

      await manager.sendChatMessage(
        thread,
        content,
        currentReferences,
        currentTopic.current,
        context,
        undefined,
        state.customInstructions,
        state.model,
      )
    },
    [context, currentReferences, currentTopic, manager, state.customInstructions, state.model, thread],
  )

  useEffect(() => {
    const message: string | null = copilotLocalStorage.getEntrypointMessage()
    if (message) {
      copilotLocalStorage.setEntrypointMessage(null)
      // eslint-disable-next-line @eslint-react/web-api/no-leaked-timeout
      setTimeout(() => {
        void handleUserSubmit(message)
      }, 100)
    }
  }, [handleUserSubmit])

  useEffect(() => {
    const timeout = window.setTimeout(() => {
      textAreaRef.current?.focus()
    }, 1)
    return () => {
      window.clearTimeout(timeout)
    }
  }, [textAreaRef])

  // Sidebar optimization for narrow and wide screens
  const containerRef = useRef<HTMLDivElement>(null)

  // Initialize isFloating based on window.innerWidth
  const [isFloating, setIsFloating] = useState<boolean>(() => {
    if (typeof window !== 'undefined') {
      return window.innerWidth <= 1024
    } else {
      return false
    }
  })

  // Initialize isSidebarPinned based on window.innerWidth
  const [isSidebarPinned, setIsSidebarPinned] = useState<boolean>(() => {
    if (typeof window !== 'undefined') {
      if (window.innerWidth > 1024) {
        return copilotLocalStorage.getImmersiveSidebarCollapsedState() ?? true
      } else {
        return false
      }
    } else {
      return copilotLocalStorage.getImmersiveSidebarCollapsedState() ?? true
    }
  })

  const [isSidebarVisible, setIsSidebarVisible] = useState(false)

  const handleToggleSidebar = () => {
    if (isFloating) {
      // width is less than or equal to 1024
      setIsSidebarVisible(!isSidebarVisible)
    } else {
      // width is greater than 1024
      const newPinnedState = !isSidebarPinned
      setIsSidebarPinned(newPinnedState)
      copilotLocalStorage.setImmersiveSidebarCollapsedState(newPinnedState)
    }
  }

  useEffect(() => {
    if (!containerRef.current) return

    // Check the container width and update isFloating
    const checkContainerWidth = () => {
      const width = containerRef.current?.clientWidth
      if (width !== undefined) {
        if (width <= 1024) {
          setIsFloating(true)
          // Ensure isSidebarPinned is false when width <= 1024
          setIsSidebarPinned(false)
        } else {
          setIsFloating(false)
          setIsSidebarVisible(false) // isSidebarVisible is always false when width > 1024
          // Restore isSidebarPinned from local storage if available
          const pinnedState = copilotLocalStorage.getImmersiveSidebarCollapsedState() ?? true
          setIsSidebarPinned(pinnedState)
        }
      }
    }

    const resizeObserver = new ResizeObserver(() => {
      checkContainerWidth()
    })

    resizeObserver.observe(containerRef.current)

    // Check the width initially
    checkContainerWidth()

    return () => {
      resizeObserver.disconnect()
    }
  }, [isSidebarVisible])

  // Compute effective values based on container width
  const effectiveIsSidebarPinned = !isFloating && isSidebarPinned
  const effectiveIsSidebarVisible = isFloating ? isSidebarVisible : false

  return (
    <div className={clsx(classes.container)} data-hpc>
      {copilotFeatureFlags.immersiveTitleFavicon && <span data-favicon-override="/favicons/favicon-copilot.svg" />}
      <div className={classes.left} ref={containerRef}>
        <Sidebar
          isVisible={effectiveIsSidebarVisible}
          isPinned={effectiveIsSidebarPinned}
          isFloating={isFloating}
          onToggle={handleToggleSidebar}
        />
        <div className={classes.main} data-testid="chat-layout">
          <Header />
          <div className={classes.content}>
            <ImmersiveChat key={state.selectedThreadID} />
          </div>
          <div className={classes.footer}>
            <div className={classes.chatInputContainer}>
              <TopicIndicator />
              <ChatInput
                key={selectedThreadID} // re-initialize when we switch threads
                textAreaRef={textAreaRef}
                onSubmit={handleUserSubmit}
                isLoading={state.isWaitingOnCopilot || state.slashCommandLoading.state === 'loading'}
                isStreaming={!!state.streamingMessage}
              />
            </div>
          </div>
        </div>
      </div>
      {copilotFeatureFlags.immersiveFilePreview && (
        <div className={clsx(classes.previewPane, previewPaneOpen && classes.active)}>
          <div className={classes.viewer}>
            <ContentPreview
              onClose={() => {
                setPreviewPaneOpen(false)
                setTimeout(() => {
                  clearPreviewItems()
                }, 250)
              }}
            />
          </div>
        </div>
      )}
    </div>
  )
}

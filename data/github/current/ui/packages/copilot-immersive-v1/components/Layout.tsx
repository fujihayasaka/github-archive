import {useAttachments} from '@github-ui/attachments'
import {ChatInput} from '@github-ui/copilot-chat/components/ChatInput'
import {useEntitlement} from '@github-ui/copilot-chat/components/quota/EntitlementContext'
import {usePlugin} from '@github-ui/copilot-chat/plugin/registry'
import type {CopilotChatReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {copilotLocalStorage} from '@github-ui/copilot-chat/utils/copilot-local-storage'
import {useChatState, useChatStateValue} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/utils/CopilotChatManagerContext'
import {isCopilotSpacesListPath} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import type {DotcomFileAttachment} from '@github-ui/copilot-chat/utils/uploadable-file-attachment'
import {clsx} from 'clsx'
import {useCallback, useEffect, useRef, useState} from 'react'

import {useIsSharedThread} from '../hooks/use-is-shared-thread'
import {useRouteThreadId} from '../hooks/use-route-thread-id'
import {ChatInputBanners} from './ChatInputBanners'
import {
  getEditedFiles,
  makeItemFromFileReference,
  makeItemFromIssueReference,
  makeReferenceFromFile,
} from './ContentPreview/content-preview-types'
import {ContentPreview} from './ContentPreview/ContentPreview'
import {useContentPreview} from './ContentPreview/ContentPreviewContext'
import {Header} from './Header'
import {ImmersiveChat} from './ImmersiveChat'
import styles from './Layout.module.css'
import {QuotaExceededBanner} from './Quota/QuotaExceededBanner'
import {QuotaExceededEmptyState} from './Quota/QuotaExceededEmptyState'
import {Sidebar} from './Sidebar'
import {SpacesView} from './Spaces/SpacesView'

const SIDEBAR_FLOATING_BREAKPOINT = 1024
const PREVIEW_PANE_FULLSCREEN_BREAKPOINT = 1280

export function Layout() {
  const state = useChatState()
  const {currentReferences, context, selectedThreadID, customCopilots} = state
  const manager = useChatManager()
  const {chatQuotaExceeded, reloadQuota} = useEntitlement()

  const thread = manager.getSelectedThread(state)
  const chatTextAreaRef = useRef<HTMLTextAreaElement>(null)
  const textAreaRef = chatTextAreaRef
  const currentTopic = useRef(state.currentTopic)

  const {items, previewPaneOpen, removeItems, openItem, updateItem, openPreviewPane} = useContentPreview()
  const activePlugin = usePlugin(useChatStateValue('activePlugin'))

  const isSharedThread = useIsSharedThread()
  const threadId = useRouteThreadId()

  const customCopilotsFlag = copilotFeatureFlags.customCopilots
  const isSpaceList = customCopilotsFlag && isCopilotSpacesListPath()

  useEffect(() => {
    currentTopic.current = state.currentTopic
  }, [state.currentTopic])

  const [attachmentsState, attachmentApi] = useAttachments()

  const onInputReferenceClick = useCallback(
    (event: React.MouseEvent<HTMLAnchorElement>, reference: CopilotChatReference) => {
      let item
      if (reference.type === 'issue') {
        item = makeItemFromIssueReference(reference)
      } else if (reference.type === 'file') {
        item = makeItemFromFileReference(reference)
      }
      if (item) {
        updateItem(item)
        openItem(item.id)
        openPreviewPane()
        event.preventDefault()
      }
    },
    [openItem, openPreviewPane, updateItem],
  )

  const handleUserSubmit = useCallback(
    async (content: string) => {
      reloadQuota()

      const trimmedContent = content.trim()
      if (trimmedContent === '') return

      const attachments = attachmentsState.attachments as DotcomFileAttachment[]
      attachmentApi.reset()

      // find files the user has edited and attach them as references
      const editedFiles = getEditedFiles(items)
      const editedFileReferences = editedFiles.map(makeReferenceFromFile)
      const references = [...currentReferences, ...editedFileReferences]
      // clear the edited files
      removeItems(editedFiles.map(f => f.id))

      const chatMessageParams = {
        thread,
        content,
        references,
        topic: currentTopic.current,
        context,
        customInstructions: state.customInstructions,
        model: state.model,
        customCopilotId: state.customCopilotId,
        attachments,
      }

      if (isSharedThread) {
        const duplicate = await manager.continueSharedThread(threadId!)

        if (duplicate) {
          const {thread: newThread, messages} = duplicate
          const parentMessageId = messages.at(-1)?.id
          await manager.sendChatMessage({...chatMessageParams, thread: newThread, parentMessageId})
        }
      } else {
        await manager.sendChatMessage(chatMessageParams)
      }
    },
    [
      reloadQuota,
      attachmentsState.attachments,
      attachmentApi,
      isSharedThread,
      items,
      manager,
      thread,
      currentReferences,
      context,
      state.customInstructions,
      state.model,
      state.customCopilotId,
      removeItems,
      threadId,
    ],
  )

  useEffect(() => {
    const message: string | null = copilotLocalStorage.getEntrypointMessage()
    if (message && !chatQuotaExceeded) {
      copilotLocalStorage.setEntrypointMessage(null)
      // eslint-disable-next-line @eslint-react/web-api/no-leaked-timeout
      setTimeout(() => {
        void handleUserSubmit(message)
      }, 100)
    }
  }, [handleUserSubmit, chatQuotaExceeded])

  const focusChatInput = useCallback(() => {
    window.setTimeout(() => {
      textAreaRef.current?.focus()
    }, 1)
    reloadQuota()
  }, [reloadQuota, textAreaRef])

  // Sidebar optimization for narrow and wide screens
  const sidebarLayoutContainerRef = useRef<HTMLDivElement>(null)

  // Initialize isFloating based on window.innerWidth
  const [isSidebarFloating, setIsSidebarFloating] = useState<boolean>(() => {
    if (sidebarLayoutContainerRef.current) {
      return sidebarLayoutContainerRef.current.clientWidth <= SIDEBAR_FLOATING_BREAKPOINT
    } else {
      return false
    }
  })

  // Initialize isSidebarPinned based on window.innerWidth
  const [isSidebarPinned, setIsSidebarPinned] = useState<boolean>(() => {
    if (sidebarLayoutContainerRef.current) {
      if (sidebarLayoutContainerRef.current.clientWidth > SIDEBAR_FLOATING_BREAKPOINT) {
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
    if (isSidebarFloating) {
      setIsSidebarVisible(!isSidebarVisible)
    } else {
      const newPinnedState = !isSidebarPinned
      setIsSidebarPinned(newPinnedState)
      copilotLocalStorage.setImmersiveSidebarCollapsedState(newPinnedState)
    }
  }

  useEffect(() => {
    if (!sidebarLayoutContainerRef.current) return

    const checkContainerWidth = () => {
      const width = sidebarLayoutContainerRef.current?.clientWidth
      if (width !== undefined) {
        if (width <= SIDEBAR_FLOATING_BREAKPOINT) {
          setIsSidebarFloating(true)
          setIsSidebarPinned(false)
        } else {
          setIsSidebarFloating(false)
          setIsSidebarVisible(false)
          const pinnedState = copilotLocalStorage.getImmersiveSidebarCollapsedState() ?? true
          setIsSidebarPinned(pinnedState)
        }
      }
    }

    const resizeObserver = new ResizeObserver(() => {
      checkContainerWidth()
    })

    resizeObserver.observe(sidebarLayoutContainerRef.current)

    checkContainerWidth()

    return () => {
      resizeObserver.disconnect()
    }
  }, [isSidebarVisible])

  const effectiveIsSidebarPinned = !isSidebarFloating && isSidebarPinned
  const effectiveIsSidebarVisible = isSidebarFloating ? isSidebarVisible : false

  // Preview pane fullscreen and sidebar floating calculations use different containers because they are dependent on
  // each other; for the same screen width there may be room for a pinned sidebar with the browser closed but not with
  // the browser open -- the browser changes the amount of available space
  const outerLayoutContainerRef = useRef<HTMLDivElement>(null)
  const [isPreviewPaneFullscreen, setIsPreviewPaneFullscreen] = useState<boolean>(() => {
    if (outerLayoutContainerRef.current) {
      return outerLayoutContainerRef.current.clientWidth <= PREVIEW_PANE_FULLSCREEN_BREAKPOINT
    } else {
      return false
    }
  })

  useEffect(() => {
    if (!outerLayoutContainerRef.current) return

    const checkContainerWidth = () => {
      const width = outerLayoutContainerRef.current?.clientWidth
      if (width !== undefined) setIsPreviewPaneFullscreen(width <= PREVIEW_PANE_FULLSCREEN_BREAKPOINT)
    }

    const resizeObserver = new ResizeObserver(checkContainerWidth)
    resizeObserver.observe(outerLayoutContainerRef.current)

    checkContainerWidth()

    return () => resizeObserver.disconnect()
  }, [])

  return (
    <div
      className={clsx(styles.container, isPreviewPaneFullscreen && styles.fullscreenPreviewPane)}
      data-testid="chat-layout"
      data-hpc
      ref={outerLayoutContainerRef}
    >
      <span data-favicon-override="/favicons/favicon-copilot.svg" />
      <div className={styles.left} ref={sidebarLayoutContainerRef}>
        <Sidebar
          isVisible={effectiveIsSidebarVisible}
          isPinned={effectiveIsSidebarPinned}
          isFloating={isSidebarFloating}
          onNewThread={focusChatInput}
          onToggle={handleToggleSidebar}
        />
        <div className={styles.main}>
          {isSpaceList ? (
            <SpacesView copilotSpaces={customCopilots} />
          ) : (
            <>
              <Header />
              {!state.selectedThreadID && chatQuotaExceeded ? (
                <QuotaExceededEmptyState />
              ) : (
                <>
                  <div className={styles.content}>
                    <ImmersiveChat
                      key={state.selectedThreadID}
                      isMobile={isPreviewPaneFullscreen}
                      onSubmit={handleUserSubmit}
                    />
                  </div>
                  {(!isSharedThread || copilotFeatureFlags.copilotDuplicateThread) && (
                    <div className={styles.footer}>
                      <div className={styles.chatInputContainer}>
                        {!chatQuotaExceeded ? (
                          state.customCopilotId && !state.selectedThreadID ? (
                            <></>
                          ) : (
                            <>
                              <ChatInputBanners />
                              <ChatInput
                                key={selectedThreadID}
                                textAreaRef={textAreaRef}
                                onSubmit={handleUserSubmit}
                                isStreaming={!!state.streamingMessage}
                                size="large"
                                onClickReference={onInputReferenceClick}
                              />
                            </>
                          )
                        ) : (
                          <QuotaExceededBanner />
                        )}
                      </div>
                    </div>
                  )}
                </>
              )}
            </>
          )}
        </div>
      </div>
      <div
        className={clsx(
          styles.previewPane,
          previewPaneOpen && styles.active,
          activePlugin?.widePreviewArea && styles.wide,
        )}
      >
        <div className={clsx(styles.viewer, activePlugin?.widePreviewArea && styles.wide)}>
          <ContentPreview returnFocusRef={textAreaRef} />
        </div>
      </div>
    </div>
  )
}

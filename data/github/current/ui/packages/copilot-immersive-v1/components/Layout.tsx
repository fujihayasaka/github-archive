import {useEntitlement} from '@github-ui/copilot-chat/components/quota/EntitlementContext'
import type {ImmersivePlugin} from '@github-ui/copilot-chat/plugin'
import {usePlugin} from '@github-ui/copilot-chat/plugin/registry'
import {copilotLocalStorage} from '@github-ui/copilot-chat/utils/copilot-local-storage'
import {useChatState, useChatStateValue} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {
  isCopilotSpaceEditPath,
  isCopilotSpacesCreatePath,
  isCopilotSpacesListPath,
  useRouteSpaceId,
} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {useCustomCopilotsEnabled, useManagedFetchCustomCopilots} from '@github-ui/custom-copilots/hooks'
import {clsx} from 'clsx'
import {useCallback, useEffect, useRef, useState} from 'react'
import {useLocation} from 'react-router-dom'

import {useAutoPreviewReference} from '../hooks/use-auto-preview-reference'
import {ContentPreview} from './ContentPreview/ContentPreview'
import {useContentPreview} from './ContentPreview/ContentPreviewContext'
import {ConversationView} from './ConversationView'
import styles from './Layout.module.css'
import {Sidebar} from './Sidebar'
import {SpacesConversation} from './Spaces/SpacesConversation'
import {SpacesEditPage} from './Spaces/SpacesEditPage'
import {SpacesListPage} from './Spaces/SpacesListPage'
import {SpacesNewPage} from './Spaces/SpacesNewPage'

const SIDEBAR_FLOATING_BREAKPOINT = 1024
const PREVIEW_PANE_FULLSCREEN_BREAKPOINT = 1280

export function Layout() {
  const state = useChatState()
  const {customCopilots} = state
  const {reloadQuota} = useEntitlement()

  const textAreaRef = useRef<HTMLTextAreaElement>(null)

  const {previewPaneOpen} = useContentPreview()
  const activePlugin = usePlugin(useChatStateValue('activePlugin'))
  const location = useLocation()

  const customCopilotsEnabled = useCustomCopilotsEnabled()
  const isSpaceList = customCopilotsEnabled && isCopilotSpacesListPath()
  const isCreateSpaceRoute = customCopilotsEnabled && isCopilotSpacesCreatePath()
  const isEditSpaceRoute = customCopilotsEnabled && isCopilotSpaceEditPath()
  const customCopilotId = useRouteSpaceId()

  useManagedFetchCustomCopilots(customCopilotsEnabled)

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
      // width is 0 in testing
      if (width !== undefined && width > 0) setIsPreviewPaneFullscreen(width <= PREVIEW_PANE_FULLSCREEN_BREAKPOINT)
    }

    const resizeObserver = new ResizeObserver(checkContainerWidth)
    resizeObserver.observe(outerLayoutContainerRef.current)

    checkContainerWidth()

    return () => resizeObserver.disconnect()
  }, [])

  // Auto-preview reference if URL contains reference_id
  useAutoPreviewReference()

  return (
    <div
      className={clsx(
        styles.container,
        !activePlugin && isPreviewPaneFullscreen && styles.fullscreenPreviewPane,
        activePlugin?.fullscreenPreviewArea && styles.fullscreenPluginPane,
      )}
      data-testid="chat-layout"
      data-hpc
      ref={outerLayoutContainerRef}
    >
      <span data-favicon-override="/favicons/favicon-copilot.svg" />
      {activePlugin?.PageComponent && activePlugin?.matchPage?.(location) ? (
        <div className={styles.main}>
          <PluginPageContent plugin={activePlugin} />
        </div>
      ) : (
        <>
          <div
            className={styles.left}
            ref={sidebarLayoutContainerRef}
            hidden={isPreviewPaneFullscreen && previewPaneOpen}
          >
            {isCreateSpaceRoute || isEditSpaceRoute ? null : (
              <Sidebar
                isVisible={effectiveIsSidebarVisible}
                isPinned={effectiveIsSidebarPinned}
                isFloating={isSidebarFloating}
                onNewThread={focusChatInput}
                onToggle={handleToggleSidebar}
              />
            )}
            <div className={styles.main}>
              {isSpaceList ? (
                <SpacesListPage copilotSpaces={customCopilots} />
              ) : isCreateSpaceRoute ? (
                <SpacesNewPage />
              ) : isEditSpaceRoute ? (
                <SpacesEditPage />
              ) : activePlugin?.ViewComponent && activePlugin?.matchView?.(location) ? (
                <PluginViewContent plugin={activePlugin} />
              ) : customCopilotId ? (
                <SpacesConversation
                  customCopilotId={customCopilotId}
                  selectedThreadID={state.selectedThreadID}
                  textAreaRef={textAreaRef}
                />
              ) : (
                <ConversationView
                  isMobile={isPreviewPaneFullscreen}
                  textAreaRef={textAreaRef}
                  key={state.selectedThreadID}
                  isSidebarOpen={isSidebarFloating ? effectiveIsSidebarVisible : effectiveIsSidebarPinned}
                />
              )}
            </div>
          </div>
          <div className={clsx(styles.previewPane, previewPaneOpen && styles.active)}>
            <div className={clsx(styles.viewer)}>
              <ContentPreview returnFocusRef={textAreaRef} />
            </div>
          </div>
        </>
      )}
    </div>
  )
}

function PluginPageContent({plugin}: {plugin: ImmersivePlugin}) {
  const state = useChatState()
  const {PageComponent} = plugin
  return PageComponent ? <PageComponent chatState={state} plugin={plugin} /> : null
}

function PluginViewContent({plugin}: {plugin: ImmersivePlugin}) {
  const state = useChatState()
  const {closePreviewPane, openPreviewPane} = useContentPreview()
  const {ViewComponent} = plugin
  return ViewComponent ? (
    <ViewComponent
      chatState={state}
      closePreviewPane={closePreviewPane}
      openPreviewPane={openPreviewPane}
      plugin={plugin}
    />
  ) : null
}

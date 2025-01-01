import {COPILOT_PATH} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/utils/CopilotChatManagerContext'
import {useCustomCopilotsEnabled} from '@github-ui/custom-copilots/hooks'
import {sendEvent} from '@github-ui/hydro-analytics'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {SidebarCollapseIcon, SidebarExpandIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {clsx} from 'clsx'
import {useEffect, useId, useRef} from 'react'
import {Link as RouterLink} from 'react-router-dom'

import {useIsSharedThread} from '../hooks/use-is-shared-thread'
import {useNavigateToNewThread} from '../hooks/use-navigate-to-new-thread'
import {useContentPreview} from './ContentPreview/ContentPreviewContext'
import {ConversationList} from './ConversationList'
import {ErrorFallback} from './ErrorFallback'
import ComposeIcon from './Icons/ComposeIcon'
import {ServiceList} from './Service/ServiceList'
import styles from './Sidebar.module.css'

interface SidebarProps {
  isVisible: boolean
  isPinned: boolean
  isFloating: boolean
  onNewThread: () => void
  onToggle: () => void
}

export function Sidebar({isVisible, isPinned, isFloating, onNewThread, onToggle}: SidebarProps) {
  const state = useChatState()
  const {threads, selectedThreadID} = state
  const isSidebarOpen = isFloating ? isVisible : isPinned

  const manager = useChatManager()
  const threadsLoaded = useRef(false)
  const navigateToNewThread = useNavigateToNewThread()
  const isSharedThread = useIsSharedThread()
  const {closePreviewPane} = useContentPreview()
  const customCopilotsEnabled = useCustomCopilotsEnabled()
  // the immersiveServiceNavigation flag checks for customCopilots, pipesPlugin, or workbenchPlugin,
  // but doesn't have knowledge of feature preview enrollment, which is another way to enable customCopilots
  const serviceNav = copilotFeatureFlags.immersiveServiceNavigation || customCopilotsEnabled

  useEffect(() => {
    if (threads.size === 0 && !threadsLoaded.current) {
      threadsLoaded.current = true
      void manager.fetchThreads()
    }
  }, [threads, manager, state])

  const toggleFloatingSidebar = () => {
    if (isFloating && isVisible) {
      onToggle()
    }
  }

  const handleSidebarClick = () => {
    toggleFloatingSidebar()
    closePreviewPane()
  }

  const sidebarRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (isVisible && isFloating) {
      const handleClickOutside = (event: MouseEvent | TouchEvent) => {
        if (sidebarRef.current && !sidebarRef.current.contains(event.target as Node)) {
          onToggle()
        }
      }

      document.addEventListener('mousedown', handleClickOutside)
      document.addEventListener('touchstart', handleClickOutside, {passive: true})

      return () => {
        document.removeEventListener('mousedown', handleClickOutside)
        document.removeEventListener('touchstart', handleClickOutside)
      }
    }
  }, [isVisible, isFloating, onToggle])

  const id = useId()

  return (
    <aside
      aria-labelledby={`${id}-copilot-navigation`}
      ref={sidebarRef}
      className={clsx(styles.container, isVisible && styles.visible, isPinned && styles.pinned)}
    >
      <div className={styles.header}>
        <h2 id={`${id}-copilot-navigation`} className="sr-only">
          Copilot navigation
        </h2>
        <IconButton
          icon={isSidebarOpen ? SidebarExpandIcon : SidebarCollapseIcon}
          aria-label={isSidebarOpen ? 'Close conversations' : 'Open conversations'}
          onClick={() => {
            onToggle()
            if (isSidebarOpen) {
              sendEvent('dotcom_chat.activate', {target: 'SIDEBAR_EXPAND', mode: 'immersive'})
            } else {
              sendEvent('dotcom_chat.activate', {target: 'SIDEBAR_COLLAPSE', mode: 'immersive'})
            }
          }}
          variant="default"
        />
        <IconButton
          as={RouterLink}
          to={COPILOT_PATH}
          icon={ComposeIcon}
          aria-label="New conversation"
          onClick={async e => {
            if (e.metaKey || e.ctrlKey) return
            e.preventDefault()

            toggleFloatingSidebar()
            await navigateToNewThread({clearTopic: true, includeThreads: false})
            onNewThread()

            sendEvent('dotcom_chat.activate', {target: 'SIDEBAR_CONVERSATION_NEW', mode: 'immersive'})
          }}
          variant="default"
        />
      </div>
      <div className={styles.sidebar}>
        <ErrorBoundary fallback={<SidebarContentsFallback />}>
          <div className={styles.conversations}>
            <nav aria-labelledby={`${id}-quick-links`} className={styles.quicklinks}>
              <h3 id={`${id}-quick-links`} className="sr-only">
                Quick links
              </h3>
              {serviceNav && <ServiceList toggleFloatingSidebar={handleSidebarClick} />}
            </nav>
            <ConversationList
              selectedItemID={isSharedThread ? null : selectedThreadID}
              loadingState={state.threadsLoading.state}
              onConversationSelect={handleSidebarClick}
            />
          </div>
        </ErrorBoundary>
      </div>
    </aside>
  )
}

function SidebarContentsFallback() {
  return (
    <div className={styles.blankslateContainer}>
      <ErrorFallback regionName="The conversations menu" />
    </div>
  )
}

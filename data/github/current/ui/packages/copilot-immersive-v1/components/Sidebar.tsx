import {COPILOT_PATH} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/utils/CopilotChatManagerContext'
import {sendEvent} from '@github-ui/hydro-analytics'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {AlertIcon, SidebarCollapseIcon, SidebarExpandIcon} from '@primer/octicons-react'
import {IconButton, Link} from '@primer/react'
import {Blankslate} from '@primer/react/experimental'
import {clsx} from 'clsx'
import {useEffect, useRef} from 'react'
import {Link as RouterLink} from 'react-router-dom'

import {useIsSharedThread} from '../hooks/use-is-shared-thread'
import {useNavigateToNewThread} from '../hooks/use-navigate-to-new-thread'
import {ConversationList} from './ConversationList'
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
  const {threads, selectedThreadID, customCopilotId} = state
  const isSidebarOpen = isFloating ? isVisible : isPinned

  const manager = useChatManager()
  const threadsLoaded = useRef(false)
  const navigateToNewThread = useNavigateToNewThread()
  const isSharedThread = useIsSharedThread()
  const serviceNav = copilotFeatureFlags.immersiveServiceNavigation

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

  return (
    <div ref={sidebarRef} className={clsx(styles.container, isVisible && styles.visible, isPinned && styles.pinned)}>
      <div className={styles.header}>
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
            {serviceNav && <ServiceList />}
            <ConversationList
              selectedItemID={isSharedThread ? null : selectedThreadID || String(customCopilotId)}
              loadingState={state.threadsLoading.state}
              onConversationSelect={toggleFloatingSidebar}
            />
          </div>
        </ErrorBoundary>
      </div>
    </div>
  )
}

function SidebarContentsFallback() {
  return (
    <div className={styles.blankslateContainer}>
      <Blankslate>
        <Blankslate.Visual>
          <AlertIcon />
        </Blankslate.Visual>
        <Blankslate.Heading>Something went wrong</Blankslate.Heading>
        <Blankslate.Description>
          The conversations list is temporarily unavailable due to an unknown error. Try reloading the page or, if the
          error persists,{' '}
          <Link href="https://support.github.com/" inline>
            contact support
          </Link>
          .
        </Blankslate.Description>
      </Blankslate>
    </div>
  )
}

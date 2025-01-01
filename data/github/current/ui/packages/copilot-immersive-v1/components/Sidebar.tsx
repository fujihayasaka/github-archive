import {COPILOT_PATH, threadName} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import type {CopilotChatThread} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/utils/CopilotChatManagerContext'
import {sendEvent} from '@github-ui/hydro-analytics'
import {useNavigate} from '@github-ui/use-navigate'
import {SidebarCollapseIcon, SidebarExpandIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {clsx} from 'clsx'
import {useCallback, useEffect, useMemo, useRef} from 'react'
import {Link as RouterLink} from 'react-router-dom'

import {clearThreadTimePatch, getThreadTimePatch} from '../utils/local-storage'
import ComposeIcon from './ComposeIcon'
import {ConversationList, type ConversationListItem} from './ConversationList'
import styles from './Sidebar.module.css'

interface SidebarProps {
  isVisible: boolean
  isPinned: boolean
  isFloating: boolean
  onToggle: () => void
}

export function Sidebar({isVisible, isPinned, isFloating, onToggle}: SidebarProps) {
  const state = useChatState()
  const {threads, selectedThreadID} = state
  const isSidebarOpen = isFloating ? isVisible : isPinned

  const manager = useChatManager()
  const threadsLoaded = useRef(false)
  const navigate = useNavigate()

  const items = useMemo(() => {
    patchThreadTime(threads)
    return manager.sortThreads(threads).map(thread => ({
      id: thread.id,
      text: threadName(thread),
      href: `${COPILOT_PATH}/c/${thread.id}`,
      date: new Date(thread.updatedAt),
    }))
  }, [threads, manager])

  const handleThreadDelete = useCallback(
    async (item: ConversationListItem) => {
      const threadToDelete = threads.get(item.id)
      if (threadToDelete) {
        // navigate away before deleting
        if (item.id === selectedThreadID) navigate(COPILOT_PATH)
        await manager.deleteThread(threadToDelete)
      }
    },
    [threads, manager, navigate, selectedThreadID],
  )

  const handleThreadRename = useCallback(
    async (item: ConversationListItem, name: string) => {
      const threadToRename = threads.get(item.id)
      if (threadToRename) {
        await manager.renameThread(threadToRename, name)
      }
    },
    [threads, manager],
  )

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
          aria-label={isSidebarOpen ? 'Close sidebar' : 'Open sidebar'}
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
          onClick={() => {
            toggleFloatingSidebar()
            sendEvent('dotcom_chat.activate', {target: 'SIDEBAR_CONVERSATION_NEW', mode: 'immersive'})
          }}
          variant="default"
        />
      </div>
      <div className={styles.sidebar}>
        <div className={styles.conversations}>
          <ConversationList
            items={items}
            selectedItemID={selectedThreadID}
            onDelete={handleThreadDelete}
            onRename={handleThreadRename}
            loadingState={state.threadsLoading.state}
            onConversationSelect={toggleFloatingSidebar}
          />
        </div>
      </div>
    </div>
  )
}

/**
 * When we create a new thread, we might reuse an older, empty thread. In that case, we need to update the thread's
 * updatedAt time to the current time so that it appears at the top of the thread list. We store this hack in local
 * storage so that it persists across page navigations.
 */
function patchThreadTime(threads: Map<string, CopilotChatThread>) {
  const patch = getThreadTimePatch()
  if (patch) {
    const thread = threads.get(patch.threadID)
    if (thread) {
      if (Date.parse(thread.updatedAt) <= patch.updatedAt) {
        thread.updatedAt = new Date(patch.updatedAt).toJSON()
      } else {
        clearThreadTimePatch()
      }
    }
  }
}

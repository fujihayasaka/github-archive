import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {COPILOT_PATH, threadName} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import type {LoadingStateState} from '@github-ui/copilot-chat/utils/copilot-chat-reducer'
import type {CopilotChatThread} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {sendEvent} from '@github-ui/hydro-analytics'
import {KebabHorizontalIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Heading, IconButton, Text} from '@primer/react'
import {SkeletonText} from '@primer/react/experimental'
import {useCallback, useId, useMemo, useRef, useState} from 'react'
import {flushSync} from 'react-dom/profiling'
import {Link} from 'react-router-dom'

import {useBooleanState} from '../hooks/use-boolean-state'
import {clearThreadTimePatch, getThreadTimePatch} from '../utils/local-storage'
import {type ConversationActionDialogName, ConversationActionDialogs, ConversationActions} from './ConversationActions'
import classes from './ConversationList.module.css'

export interface ConversationListItem {
  id: string
  text: string
  leadingVisual?: React.ReactNode
  href?: string
  date: Date
}

interface ConversationListProps {
  selectedItemID?: string | null
  loadingState: LoadingStateState
  onConversationSelect: () => void
}

function groupItemsByDate(items: ConversationListItem[]) {
  const today = new Date()
  const yesterday = new Date(today)
  yesterday.setDate(today.getDate() - 1)
  const last7Days = new Date(today)
  last7Days.setDate(today.getDate() - 7)
  const last30Days = new Date(today)
  last30Days.setDate(today.getDate() - 30)

  const todayItems: ConversationListItem[] = []
  const yesterdayItems: ConversationListItem[] = []
  const last7DaysItems: ConversationListItem[] = []
  const last30DaysItems: ConversationListItem[] = []

  for (const item of items) {
    if (item.date.toDateString() === today.toDateString()) {
      todayItems.push(item)
    } else if (item.date.toDateString() === yesterday.toDateString()) {
      yesterdayItems.push(item)
    } else if (item.date > last7Days) {
      last7DaysItems.push(item)
    } else if (item.date > last30Days) {
      last30DaysItems.push(item)
    }
  }

  const grouped = {
    Today: todayItems,
    Yesterday: yesterdayItems,
    'Last 7 days': last7DaysItems,
    'Last 30 days': last30DaysItems,
  }

  return grouped
}

export function ConversationList({selectedItemID, loadingState, onConversationSelect}: ConversationListProps) {
  const manager = useChatManager()
  const {threads} = useChatState()

  const ungroupedItems = useMemo(() => {
    patchThreadTime(threads)
    return manager.sortThreads(threads).map(thread => ({
      id: thread.id,
      text: threadName(thread),
      href: `${COPILOT_PATH}/c/${thread.id}`,
      date: new Date(thread.updatedAt),
    }))
  }, [threads, manager])

  const groupedItems = groupItemsByDate(ungroupedItems)
  const isEmpty = ungroupedItems.length === 0
  const isLoading = loadingState === 'loading' || loadingState === 'pending'

  const id = useId()

  return (
    <aside
      aria-labelledby={`${id}-conversations`}
      id={`${id}-conversation-list`}
      tabIndex={-1}
      className={classes.ConversationList__container}
    >
      {isEmpty && isLoading ? (
        <SkeletonText lines={5} />
      ) : isEmpty ? (
        <EmptyState />
      ) : (
        <div className={classes.ConversationList__section}>
          <h2 id={`${id}-conversations`} className="sr-only">
            Conversations
          </h2>
          {Object.entries(groupedItems).map(
            ([group, items]) =>
              items.length > 0 && (
                <nav key={group} aria-labelledby={`${id}_${group}`}>
                  <h3 id={`${id}_${group}`} className={classes.ConversationList__title}>
                    {group}
                  </h3>
                  <ul className={classes.ConversationList}>
                    {items.map(item => (
                      <ConversationListEntry
                        item={item}
                        key={item.id}
                        selectedItemId={selectedItemID ?? undefined}
                        onSelect={onConversationSelect}
                      />
                    ))}
                  </ul>
                </nav>
              ),
          )}
        </div>
      )}
    </aside>
  )
}

interface ConversationListEntryProps {
  item: ConversationListItem
  selectedItemId?: string
  onSelect: () => void
}

function ConversationListEntry({item, selectedItemId, onSelect}: ConversationListEntryProps) {
  const selected = item.id === selectedItemId
  const [dialog, setDialog] = useState<ConversationActionDialogName | null>(null)
  const [loading, startLoading, stopLoading] = useBooleanState(false)

  const anchorRef = useRef<HTMLButtonElement>(null)

  const closeDialog = useCallback(() => {
    flushSync(() => setDialog(null))
    anchorRef.current?.focus()
  }, [])

  return (
    item.href && (
      <li className={classes.ConversationList__item} key={item.id}>
        <Link
          className={classes.ConversationList__link}
          to={item.href}
          aria-current={selected ? 'page' : undefined}
          onClick={() => {
            onSelect()
            sendEvent('dotcom_chat.activate', {
              target: 'CONVERSATION_SELECT',
              threadId: item.id,
              mode: 'immersive',
            })
          }}
        >
          <span className={classes.ConversationList__text}>{item.text}</span>
        </Link>
        <span className={classes.ConversationList__context}>
          <ActionMenu anchorRef={anchorRef}>
            <ActionMenu.Anchor>
              <IconButton
                loading={loading}
                icon={KebabHorizontalIcon}
                aria-label="Manage conversation"
                variant="invisible"
                onClick={() =>
                  sendEvent('dotcom_chat.activate', {
                    target: 'CONVERSATION_CONTEXT_MENU',
                    mode: 'immersive',
                  })
                }
              />
            </ActionMenu.Anchor>
            <ActionMenu.Overlay>
              <ActionList>
                <ConversationActions onOpenDialog={setDialog} />
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        </span>
        <ConversationActionDialogs
          visibleDialog={dialog}
          onClose={closeDialog}
          threadName={item.text}
          threadId={item.id}
          selectedThreadId={selectedItemId}
          onStartLoading={startLoading}
          onFinishLoading={stopLoading}
        />
      </li>
    )
  )
}

function EmptyState() {
  return (
    <div className={classes.ConversationList__empty}>
      <Heading as="h3" sx={{fontSize: 1, mb: 2}}>
        No conversations yet
      </Heading>
      <Text sx={{color: 'fg.muted'}}>Ask Copilot anything on the right to start your first conversation.</Text>
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

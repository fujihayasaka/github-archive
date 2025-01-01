import type {LoadingStateState} from '@github-ui/copilot-chat/utils/copilot-chat-reducer'
import {sendEvent} from '@github-ui/hydro-analytics'
import {Heading, Text} from '@primer/react'
import {SkeletonText} from '@primer/react/experimental'
import {useId} from 'react'
import {Link} from 'react-router-dom'

import {ConversationMenu} from './ConversationActions'
import classes from './ConversationList.module.css'

export interface ConversationListItem {
  id: string
  text: string
  leadingVisual?: React.ReactNode
  href?: string
  date: Date
}

interface ConversationListProps {
  items: ConversationListItem[]
  selectedItemID?: string | null
  loadingState: LoadingStateState
  onDelete: (item: ConversationListItem) => Promise<void>
  onRename: (item: ConversationListItem, name: string) => Promise<void>
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

export function ConversationList({
  items: ungroupedItems,
  selectedItemID,
  loadingState,
  onDelete,
  onRename,
  onConversationSelect,
}: ConversationListProps) {
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
                    {items.map(
                      item =>
                        item.href && (
                          <li className={classes.ConversationList__item} key={item.id}>
                            <Link
                              className={classes.ConversationList__link}
                              to={item.href}
                              aria-current={item.id === selectedItemID ? 'page' : undefined}
                              onClick={() => {
                                onConversationSelect()
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
                              <ConversationMenu
                                conversationName={item.text}
                                onDelete={() => onDelete(item)}
                                onRename={name => onRename(item, name)}
                              />
                            </span>
                          </li>
                        ),
                    )}
                  </ul>
                </nav>
              ),
          )}
        </div>
      )}
    </aside>
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

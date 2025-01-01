import {isFeatureEnabled} from '@github-ui/feature-flags'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {sendEvent} from '@github-ui/hydro-analytics'
import {testIdProps} from '@github-ui/test-id-props'
import {
  CommentIcon,
  FoldIcon,
  GitMergeIcon,
  GitPullRequestClosedIcon,
  GitPullRequestDraftIcon,
  GitPullRequestIcon,
  IssueClosedIcon,
  IssueDraftIcon,
  IssueOpenedIcon,
  PersonIcon,
  SkipIcon,
  UnfoldIcon,
} from '@primer/octicons-react'
import {AvatarStack, Label, RelativeTime} from '@primer/react'
import {clsx} from 'clsx'
import {load} from 'js-yaml'
import {useEffect, useState} from 'react'

import {useContentPreview} from '../../components/ContentPreview/ContentPreviewContext'
import {useContentPreviewBlockContext} from '../ContentPreviewBlockContext'
import styles from '../issue-blocks/IssueListBlock.module.css'

interface ListItem {
  type?: 'issue' | 'pr'
  url?: string
  state?: string
  draft?: boolean
  created_at?: string
  closed_at?: string
  merged_at?: string
  title?: string
  number?: number
  labels?: string[]
  author?: string
  comments?: number
  assignees_avatar_urls?: string[]
}

const ListItem = {
  /** Being extremely defensive about the types here allows us to safely handle partial data and bad model results. */
  fromUnknown: (data: unknown): ListItem => {
    if (typeof data !== 'object' || data === null) return {}

    // There's probably a library that could do this less tediously
    const item: ListItem = {}

    if ('url' in data && typeof data.url === 'string') item.url = data.url
    if ('state' in data && typeof data.state === 'string') item.state = data.state
    if ('draft' in data && typeof data.draft === 'boolean') item.draft = data.draft
    // eslint-disable-next-line camelcase
    if ('created_at' in data && typeof data.created_at === 'string') item.created_at = data.created_at
    // eslint-disable-next-line camelcase
    if ('closed_at' in data && typeof data.closed_at === 'string') item.closed_at = data.closed_at
    // eslint-disable-next-line camelcase
    if ('merged_at' in data && typeof data.merged_at === 'string') item.merged_at = data.merged_at
    if ('title' in data && typeof data.title === 'string') item.title = data.title
    if ('number' in data && typeof data.number === 'number') item.number = data.number
    if ('labels' in data && Array.isArray(data.labels)) item.labels = data.labels.filter(el => typeof el === 'string')
    if ('author' in data && typeof data.author === 'string') item.author = data.author
    if ('comments' in data && typeof data.comments === 'number') item.comments = data.comments
    if ('assignees_avatar_urls' in data && Array.isArray(data.assignees_avatar_urls))
      // eslint-disable-next-line camelcase
      item.assignees_avatar_urls = data.assignees_avatar_urls.filter(el => typeof el === 'string')

    return item
  },
}

function parseGitHubIssueUrl(url: string) {
  const pattern = /^https?:\/\/[^/]+\/([^/]+)\/([^/]+)\/issues\/(\d+)(\/.*)?$/
  const match = pattern.exec(url)
  if (!match) {
    return {}
  }
  const number = parseInt(match[3] ?? '0', 10)
  return {owner: match[1], repo: match[2], number}
}

function getIconProps(item: ListItem) {
  let icon = null
  let colorClass: string | undefined

  if (item.type === 'issue') {
    if (item.state === 'open' && !item.draft) {
      icon = <IssueOpenedIcon aria-label="Open issue" />
      colorClass = styles.open
    } else if (item.state === 'closed' && !item.draft) {
      icon = <IssueClosedIcon aria-label="Closed issue" />
      colorClass = styles.done
    } else if (item.state === 'open' && item.draft) {
      icon = <IssueDraftIcon aria-label="Draft issue" />
      colorClass = styles.draft
    } else if (item.state === 'closed' && item.draft) {
      icon = <SkipIcon aria-label="Closed draft issue" />
      colorClass = styles.draft
    }
  } else if (item.type === 'pr') {
    const isMerged = typeof item.merged_at === 'string' && item.merged_at.length > 0
    if (item.state === 'open' && !isMerged && item.draft) {
      icon = <GitPullRequestDraftIcon aria-label="Draft pull request" />
      colorClass = styles.draft
    } else if (item.state === 'open' && !isMerged && !item.draft) {
      icon = <GitPullRequestIcon aria-label="Pull request" />
      colorClass = styles.open
    } else if (item.state === 'closed' && !isMerged) {
      icon = <GitPullRequestClosedIcon aria-label="Closed pull request" />
      colorClass = styles.closed
    } else if (item.state === 'closed' && isMerged) {
      icon = <GitMergeIcon aria-label="Merged pull request" />
      colorClass = styles.done
    }
  }

  return {icon, colorClass}
}

function Description({item, isStreaming}: {item: ListItem; isStreaming: boolean}) {
  const author = item.author
  let dateValue = undefined
  let action = undefined

  if (item.merged_at) {
    dateValue = item.merged_at
    action = 'Merged'
  } else if (item.closed_at) {
    dateValue = item.closed_at
    action = 'Closed'
  } else if (item.created_at) {
    dateValue = item.created_at
    action = 'Opened'
  }

  let parsedDate = dateValue ? new Date(dateValue) : null
  if (parsedDate && isNaN(parsedDate.getTime())) parsedDate = null

  return (!author || !parsedDate) && isStreaming ? null : (
    <span className={styles.description}>
      {author} {author ? action?.toLowerCase() : action}{' '}
      {parsedDate && (
        <>
          <RelativeTime date={parsedDate} format="micro" /> ago
        </>
      )}
    </span>
  )
}

const parseListData = (yaml: string) => {
  try {
    const result = load(yaml)
    if (typeof result === 'object' && result !== null && 'data' in result && Array.isArray(result.data))
      return result.data.map(ListItem.fromUnknown)
    return null
  } catch {
    return null
  }
}

export interface ListBlockProps {
  /** List item data as YAML string. */
  data: string
  type: 'issue' | 'pr'
  isStreaming: boolean
}

export function ListBlock({data, type, isStreaming: isBlockStreaming}: ListBlockProps) {
  const [items, setItems] = useState<ListItem[]>(() => parseListData(data) ?? [])
  const {updateItem, openItem, openPreviewPane} = useContentPreview()
  const {messageId} = useContentPreviewBlockContext()
  const [collapsed, setCollapsed] = useState(true)
  const hasMoreItemsEnabled = isFeatureEnabled('copilot_issue_list_show_more')

  // Default to showing 10 items when collapsed
  const initialVisibleCount = 10
  const visibleItems = hasMoreItemsEnabled && collapsed ? items.slice(0, initialVisibleCount) : items
  const hasMoreItems = hasMoreItemsEnabled && items.length > initialVisibleCount

  // Ignore intermediate updates with bad data (partially streamed YAML)
  useEffect(() => setItems(lastParsedData => parseListData(data) ?? lastParsedData), [data])

  useEffect(() => {
    if (type === 'issue') {
      sendEvent('dotcom_chat.activate', {target: 'ISSUE_LIST_BLOCK_RENDERED', mode: 'immersive'})
    } else {
      sendEvent('dotcom_chat.activate', {target: 'PR_LIST_BLOCK_RENDERED', mode: 'immersive'})
    }
  }, [type])

  // Once complete we render the actual list
  return (
    <div>
      <ul id="issue-list" className={clsx(styles.list, isBlockStreaming && styles.streaming)}>
        {visibleItems.map((item, index) => {
          // Instead of mutating the initial item, create a new object
          const newItem = {...item, type}
          const isStreaming = isBlockStreaming && index === visibleItems.length - 1

          const {icon, colorClass} = getIconProps(newItem)
          return (
            // The items cannot reorder and we want to ensure a stable key, so it's safe to use index
            // eslint-disable-next-line @eslint-react/no-array-index-key
            <li className={styles.item} key={index}>
              <div className={styles.content}>
                <div className={clsx(colorClass, styles.icon)}>{icon}</div>
                <div className={styles.header}>
                  {
                    // While streaming it's important that we don't render the link to avoid a11y issues and let it fade in later
                    isStreaming && !newItem.title ? null : (
                      <a
                        {...testIdProps('issue-list-item-link')}
                        href={newItem.url ?? '#'}
                        className={styles.link}
                        onClick={e => {
                          if (e.metaKey || e.ctrlKey) return
                          e.preventDefault()
                          if (!newItem.url) return

                          // Only updateItem if it's an issue
                          if (newItem.type === 'issue') {
                            sendEvent('dotcom_chat.activate', {target: 'ISSUE_LIST_BLOCK_ITEM_OPEN', mode: 'immersive'})
                            const {owner, repo, number} = parseGitHubIssueUrl(newItem.url)
                            if (owner && repo && number) {
                              const id = `issue:${owner}/${repo}/${number}` as const
                              updateItem({
                                messageId,
                                name: newItem.title ?? `Issue #${number}`,
                                number,
                                owner,
                                repo,
                                id,
                                href: newItem.url,
                                type: 'issue',
                              })
                              openItem(id)
                              openPreviewPane()
                            }
                          } else {
                            sendEvent('dotcom_chat.activate', {target: 'PR_LIST_BLOCK_ITEM_OPEN', mode: 'immersive'})
                            // If it's a PR, just open the URL
                            window.open(newItem.url, '_self')
                          }
                        }}
                        target="_blank"
                        rel="noreferrer"
                      >
                        {!newItem.title && newItem.number !== undefined ? (
                          // Fall back to the number as the title
                          <span className={styles.title}>#{newItem.number}</span>
                        ) : (
                          <>
                            {newItem.title ? (
                              <span className={styles.title}>{newItem.title}</span>
                            ) : (
                              // If the issue has streamed and we never got a title _or_ a number, the AI is throwing a
                              // total hissy fit and there's nothing we can do. Hopefully this doesn't actually happen.
                              <span className={clsx(styles.title, styles.unknownTitle)}>Unknown issue</span>
                            )}
                            {newItem.number !== undefined && <span className={styles.number}>#{newItem.number}</span>}
                          </>
                        )}
                      </a>
                    )
                  }
                  <div className={styles.labels}>
                    {newItem.labels?.length
                      ? newItem.labels.map(label => (
                          <Label size="small" variant="secondary" key={label}>
                            {label}
                          </Label>
                        ))
                      : null}
                    {newItem.comments !== 0 && newItem.comments !== undefined && (
                      <Label size="small" variant="secondary">
                        <CommentIcon className={styles.labelIcon} size={12} />
                        {newItem.comments}
                      </Label>
                    )}
                  </div>
                </div>
                <Description item={newItem} isStreaming={isStreaming} />
                <div className={styles.metadata}>
                  {newItem.assignees_avatar_urls === undefined ? null : newItem.assignees_avatar_urls.length === 0 ? (
                    <div className={styles.unassignedAvatar} role="img" aria-label="Unassigned">
                      <PersonIcon size={12} />
                    </div>
                  ) : (
                    <div
                      role="img"
                      // We don't know the assignee names so we can't provide an aria-label to each avatar
                      aria-label={`${newItem.assignees_avatar_urls.length} ${
                        newItem.assignees_avatar_urls.length === 1 ? 'assignee' : 'assignees'
                      }`}
                    >
                      <AvatarStack disableExpand>
                        {newItem.assignees_avatar_urls.map(url => (
                          <GitHubAvatar key={url} src={url} alt="Assignee avatar" />
                        ))}
                      </AvatarStack>
                    </div>
                  )}
                </div>
              </div>
            </li>
          )
        })}
        {hasMoreItems && (
          <li className={styles.item}>
            <div className={clsx(styles.content, styles.toggleContent)}>
              <button
                type="button"
                className={clsx(styles.toggleButton, isBlockStreaming && styles.shimmer)}
                onClick={() => setCollapsed(!collapsed)}
                aria-expanded={!collapsed}
                aria-controls="issue-list"
              >
                <span className={styles.toggleIcon}>
                  {collapsed ? <UnfoldIcon size={16} /> : <FoldIcon size={16} />}
                </span>
                {collapsed ? `Show ${items.length - initialVisibleCount} more` : 'Show less'}
              </button>
            </div>
          </li>
        )}
      </ul>
    </div>
  )
}

import {VersionName} from '@github-ui/copilot-chat/components/VersionName'
import {disableStreamingFadeIn} from '@github-ui/copilot-markdown'
import {sendEvent} from '@github-ui/hydro-analytics'
import {IssueDraftIcon} from '@primer/octicons-react'
import {Spinner} from '@primer/react'
import {load} from 'js-yaml'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'

import {getRevisionNumber} from '../../components/ContentPreview/content-preview-types'
import {useContentPreview} from '../../components/ContentPreview/ContentPreviewContext'
import {useContentPreviewBlockContext} from '../ContentPreviewBlockContext'
import styles from './DraftIssueBlock.module.css'

export const issueOwnerAttribute = 'data-issue-owner'
export const issueRepoAttribute = 'data-issue-repo'
export const issueTitleAttribute = 'data-issue-title'
export const draftIssueBlockAttribute = 'data-draft-issue-block'

export const issueLinkBlockAttributes = [issueOwnerAttribute, issueRepoAttribute, issueTitleAttribute]

export interface DraftIssue {
  title?: string
  body?: string
  labels?: string[]
  assignees?: string[]
  repository?: string
  template?: string
  issueType?: string
  projects?: string[]
  milestone?: string
  tag?: string
  parentTag?: string
}

export const DraftIssue = {
  /** Being extremely defensive about the types here allows us to safely handle partial data and bad model results. */
  fromUnknown: (data: unknown): DraftIssue | null => {
    if (typeof data !== 'object' || data == null) return null

    // there's probably a library that could do this less tediously
    const item: DraftIssue = {}

    if ('title' in data && typeof data.title === 'string') item.title = data.title
    if ('tag' in data && typeof data.tag === 'string') item.tag = data.tag
    if ('description' in data && typeof data.description === 'string') item.body = data.description
    if ('labels' in data && Array.isArray(data.labels)) item.labels = data.labels.filter(el => typeof el === 'string')
    if ('assignees' in data && Array.isArray(data.assignees))
      item.assignees = data.assignees.filter(el => typeof el === 'string')
    if ('repository' in data && typeof data.repository === 'string') item.repository = data.repository
    if ('template' in data && typeof data.template === 'string') item.template = data.template
    if ('type' in data && typeof data.type === 'string') item.issueType = data.type
    if ('projects' in data && Array.isArray(data.projects))
      item.projects = data.projects.filter(el => typeof el === 'string')
    if ('milestone' in data && typeof data.milestone === 'string') item.milestone = data.milestone

    if ('parentTag' in data && typeof data.parentTag === 'string') {
      item.parentTag = data.parentTag
    }

    return item
  },
}

const parseIssueData = (yaml: string) => {
  try {
    const result = load(yaml)
    return DraftIssue.fromUnknown(result)
  } catch {
    return null
  }
}

export interface DraftIssueBlockProps {
  yaml: string
  isStreaming?: boolean
}

export function DraftIssueBlock({yaml, isStreaming}: DraftIssueBlockProps) {
  const [fromStreaming, setFromStreaming] = useState(isStreaming)

  useEffect(() => {
    if (isStreaming) {
      setFromStreaming(true)
    }
  }, [isStreaming])

  const {updateItem, openItem, openPreviewPane, versionedItems, items} = useContentPreview()
  const {messageId, messageIndex, autoOpenPreviewPane, hasAutoOpenedPreviewPaneRef} = useContentPreviewBlockContext()

  // Employ `useMemo + useRef` instead of `useState` to avoid asynchronous state updates
  // Since the order of versionedItems matters, we need to ensure that we call `updateItem` with the latest data
  // immediately after the YAML is changed.
  const issueRef = useRef<DraftIssue>({})
  const issue = useMemo(() => {
    const parsedIssueData = parseIssueData(yaml)
    if (parsedIssueData != null) {
      issueRef.current = parsedIssueData
      return parsedIssueData
    } else {
      // Ignore bad data due to partially streamed YAML
      return issueRef.current
    }
  }, [yaml])

  useEffect(() => sendEvent('dotcom_chat.activate', {target: 'ISSUE_DRAFT_BLOCK_RENDERED', mode: 'immersive'}), [])

  const id = issue.tag != null ? (`new-issue:${issue.tag}#${messageIndex}` as const) : undefined
  const version = id != null ? getRevisionNumber(id, versionedItems) : null
  const item = id != null ? items.get(id) : undefined
  const repository = !issue.repository && item?.type === 'new-issue' ? item.repository || '' : issue.repository

  const openDraftIssue = useCallback(
    ({userInitiated}: {userInitiated: boolean}) => {
      if (id != null) {
        openItem(id, userInitiated /* selectItem */)

        if (userInitiated || (autoOpenPreviewPane && !hasAutoOpenedPreviewPaneRef.current)) {
          openPreviewPane()
          // Copied from FileBlock.tsx
          // Suppress warning for ESLint bug that thinks refs defined in other files aren't refs.
          // eslint-disable-next-line react-hooks/react-compiler
          hasAutoOpenedPreviewPaneRef.current = true
        }

        sendEvent('dotcom_chat.activate', {target: 'BROWSER_DRAFT_ISSUE_OPENED', mode: 'immersive'})
      }
    },
    [id, openItem, openPreviewPane, autoOpenPreviewPane, hasAutoOpenedPreviewPaneRef],
  )

  // Side effect that only concerns about the changes from streaming content
  useEffect(() => {
    if (id != null) {
      updateItem({
        messageId,
        name: issue.title ?? '',
        body: issue.body,
        repository,
        id,
        type: 'new-issue',
        tag: issue.tag ?? '',
        isStreaming,
        template: issue.template,
        issueType: issue.issueType,
        milestone: issue.milestone,
        // Copilot will return arrays in arbitrary order. We need stability for versioning to work.
        assignees: issue.assignees?.sort() ?? [],
        labels: issue.labels?.sort() ?? [],
        projects: issue.projects?.sort() ?? [],
        isUserEdited: false,
      })
    }
  }, [
    id,
    isStreaming,
    repository,
    issue.assignees,
    issue.body,
    issue.tag,
    issue.title,
    issue.labels,
    issue.template,
    issue.issueType,
    issue.projects,
    issue.milestone,
    messageId,
    updateItem,
  ])

  // Side effect to automatically open the preview pane if it's the latest version
  useEffect(() => {
    if (id != null && fromStreaming) {
      openDraftIssue({userInitiated: false})
    }
  }, [id, openDraftIssue, fromStreaming])

  const onClick = useCallback(() => openDraftIssue({userInitiated: true}), [openDraftIssue])
  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.code === 'Enter' || e.code === 'Space') {
      onClick()
    }
  }

  return (
    <div className={styles.container} role="button" onClick={onClick} onKeyDown={onKeyDown} tabIndex={0}>
      {isStreaming ? (
        <Spinner size="small" className={disableStreamingFadeIn} />
      ) : (
        <IssueDraftIcon className={styles.icon} />
      )}
      <span className={styles.previewText}>{issue.title}</span>
      {version != null && <VersionName version={version} />}
    </div>
  )
}

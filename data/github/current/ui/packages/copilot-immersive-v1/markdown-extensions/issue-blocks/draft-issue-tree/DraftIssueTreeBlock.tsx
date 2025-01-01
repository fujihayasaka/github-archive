import {VersionName} from '@github-ui/copilot-chat/components/VersionName'
import {disableStreamingFadeIn} from '@github-ui/copilot-markdown'
import {NestedListView} from '@github-ui/nested-list-view'
import {NestedListItem} from '@github-ui/nested-list-view/NestedListItem'
import {NestedListItemLeadingContent} from '@github-ui/nested-list-view/NestedListItemLeadingContent'
import {NestedListItemLeadingVisual} from '@github-ui/nested-list-view/NestedListItemLeadingVisual'
import {NestedListItemTitle} from '@github-ui/nested-list-view/NestedListItemTitle'
import {IssueDraftIcon} from '@primer/octicons-react'
import {Spinner} from '@primer/react'
import {loadAll} from 'js-yaml'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'

import {getRevisionNumber} from '../../../components/ContentPreview/content-preview-types'
import {useContentPreview} from '../../../components/ContentPreview/ContentPreviewContext'
import {useContentPreviewBlockContext} from '../../ContentPreviewBlockContext'
import {DraftIssue} from '../DraftIssueBlock'
import styles from './DraftIssueTreeBlock.module.css'

export interface DraftIssueTreeBlockProps {
  data: string
  isStreaming?: boolean
}

type TreeNode = {
  item: DraftIssue
  children?: TreeNode[]
}

function parseListData(yaml: string) {
  try {
    // TODO I'm not sold on the yaml structure yet. Maybe a single document with a list of issues?
    const result = loadAll(yaml)
    if (Array.isArray(result)) {
      return result
        .map(DraftIssue.fromUnknown)
        .filter(item => !!item)
        .filter(item => !!item.tag) // Relationships require the tag value to be set
    }
    return null
  } catch {
    return null
  }
}

export function DraftIssueTreeBlock({data, isStreaming}: DraftIssueTreeBlockProps) {
  // Employ `useMemo + useRef` instead of `useState` to avoid asynchronous state updates
  // Since the order of versionedItems matters, we need to ensure that we call `updateItem` with the latest data
  // immediately after the YAML is changed.
  const issuesRef = useRef<DraftIssue[]>([])
  const issues = useMemo(() => {
    const parsed = parseListData(data)
    if (parsed) {
      issuesRef.current = parsed
    }
    return issuesRef.current
  }, [data])

  // Cache the isStreaming in case it flips before we can do anything that relies on it
  const [fromStreaming, setFromStreaming] = useState(isStreaming)
  useEffect(() => {
    if (isStreaming) {
      setFromStreaming(true)
    }
  }, [isStreaming])

  const {updateItem, openItem, openPreviewPane, versionedItems} = useContentPreview()
  const {messageId, messageIndex, autoOpenPreviewPane, hasAutoOpenedPreviewPaneRef} = useContentPreviewBlockContext()

  const getId = useCallback(
    (issue: DraftIssue) => {
      return issue.tag ? (`new-issue:${issue.tag}#${messageIndex}` as const) : undefined
    },
    [messageIndex],
  )

  // Update the tree items in the content preview context
  useEffect(() => {
    for (const issue of issues) {
      const id = getId(issue)
      if (id) {
        updateItem({
          messageId,
          type: 'new-issue',
          id,
          tag: issue.tag ?? '',
          parentTag: issue.parentTag,
          name: issue.title ?? '',
          body: issue.body,
          repository: issue.repository,
          template: issue.template,
          issueType: issue.issueType,
          milestone: issue.milestone,
          assignees: issue.assignees?.sort() ?? [],
          labels: issue.labels?.sort() ?? [],
          projects: issue.projects?.sort() ?? [],
          isUserEdited: false,
          isStreaming,
        })
      }
    }
  }, [getId, isStreaming, issues, messageId, messageIndex, updateItem])

  const openIssue = useCallback(
    (issue: DraftIssue, userInitiated: boolean) => {
      const id = getId(issue)
      if (id) {
        openItem(id, userInitiated /* selectItem */)

        if (userInitiated || (autoOpenPreviewPane && !hasAutoOpenedPreviewPaneRef.current)) {
          openPreviewPane()
          // Suppress warning for ESLint bug that thinks refs defined in other files aren't refs.
          // eslint-disable-next-line react-hooks/react-compiler
          hasAutoOpenedPreviewPaneRef.current = true
        }
      }
    },
    [getId, openItem, openPreviewPane, autoOpenPreviewPane, hasAutoOpenedPreviewPaneRef],
  )

  const rootNodes: TreeNode[] = useMemo(() => {
    // Create a map of all items
    const itemMap = issues.reduce((map, item) => {
      map.set(item.tag!, {item, children: []})
      return map
    }, new Map<string, TreeNode>())

    // Link children to their parents
    for (const item of issues) {
      if (!item.parentTag) continue
      const parentNode = itemMap.get(item.parentTag)
      const currentNode = itemMap.get(item.tag!)
      if (parentNode && currentNode) {
        parentNode.children!.push(currentNode)
      }
    }

    // Return only root nodes (nodes without a parentTag)
    return Array.from(itemMap.values()).filter(node => !node.item.parentTag)
  }, [issues])

  // Auto-open all the top-level issues while streaming
  useEffect(() => {
    if (fromStreaming) {
      for (const node of rootNodes) {
        openIssue(node.item, false)
      }
    }
  }, [fromStreaming, rootNodes, openIssue])

  const renderNestedListNode = (node: TreeNode) => {
    const id = getId(node.item)
    const version = id ? getRevisionNumber(id, versionedItems) : null
    return (
      <NestedListItem
        key={node.item.tag}
        title={
          <NestedListItemTitle
            value={node.item.title ?? ''}
            onClick={() => openIssue(node.item, true)}
            trailingBadges={
              version != null ? [<VersionName key={`${node.item.tag}#${version}`} version={version} />] : undefined
            }
          />
        }
        subItems={node.children?.length ? node.children.map(renderNestedListNode) : undefined}
        defaultExpanded
      >
        <NestedListItemLeadingContent>
          <NestedListItemLeadingVisual>
            {isStreaming ? <Spinner size="small" className={disableStreamingFadeIn} /> : <IssueDraftIcon />}
          </NestedListItemLeadingVisual>
        </NestedListItemLeadingContent>
      </NestedListItem>
    )
  }

  return (
    <>
      {rootNodes.map(node => (
        <div className={styles.container} key={node.item.tag}>
          <NestedListView title={'Draft issue hierarchy'}>{renderNestedListNode(node)}</NestedListView>
        </div>
      ))}
    </>
  )
}

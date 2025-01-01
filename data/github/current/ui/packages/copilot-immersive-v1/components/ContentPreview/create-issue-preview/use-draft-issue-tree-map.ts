import {useMemo} from 'react'

import type {DraftIssue} from '../content-preview-types'
import {useContentPreview} from '../ContentPreviewContext'

export type TreeNode<T> = {
  item: T
  parent: TreeNode<T> | null
  children: Array<TreeNode<T>>
}

export function visit<T>(node: TreeNode<T>, callback: (node: TreeNode<T>) => void): void {
  callback(node)
  for (const child of node.children) {
    visit(child, callback)
  }
}

/**
 * Convert content preview draft issue items into a tree structure.
 *
 * @returns a `Map` of all draft issues, where
 *   - `key` is the issue `tag`
 *   - `value` is a `TreeNode`, containing the draft issue, and pointers to its parent and children
 */
export function useDraftIssueTreeMap() {
  const {items, versionedItems} = useContentPreview()

  return useMemo(() => {
    const latestDraftIssues = [...versionedItems.entries()]
      .filter(([id]) => id.startsWith('new-issue:'))
      // eslint-disable-next-line @typescript-eslint/no-unused-vars
      .map(([_id, versionIds]) => {
        // This assumes we only care about the latest version of each draft issue
        // TODO sort out how to handle multiple versions of draft issues in a tree
        const latestVersionId = versionIds.at(-1)
        return latestVersionId ? items.get(latestVersionId) : undefined
      })
      .filter((x): x is DraftIssue => !!x)

    // Seed a Map of all items by tag
    const draftIssuesMap = latestDraftIssues.reduce((acc, issue) => {
      acc.set(issue.tag, {item: issue, parent: null, children: []})
      return acc
    }, new Map<string, TreeNode<DraftIssue>>())

    // Link parents and children
    for (const draftIssue of latestDraftIssues) {
      if (!draftIssue.parentTag) continue
      const parentNode = draftIssuesMap.get(draftIssue.parentTag)
      const currentNode = draftIssuesMap.get(draftIssue.tag)
      if (parentNode && currentNode) {
        currentNode.parent = parentNode
        parentNode.children.push(currentNode)
      }
    }

    // Return the complete Map; callers can decide what subtree they need
    return draftIssuesMap
  }, [items, versionedItems])
}

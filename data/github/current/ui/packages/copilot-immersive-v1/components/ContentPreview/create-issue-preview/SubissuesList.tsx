import {VersionName} from '@github-ui/copilot-chat/components/VersionName'
import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {getSelectedThread} from '@github-ui/copilot-chat/utils/get-selected-thread'
import {NestedListView} from '@github-ui/nested-list-view'
import {NestedListItem} from '@github-ui/nested-list-view/NestedListItem'
import {NestedListItemActionBar} from '@github-ui/nested-list-view/NestedListItemActionBar'
import {NestedListItemLeadingContent} from '@github-ui/nested-list-view/NestedListItemLeadingContent'
import {NestedListItemLeadingVisual} from '@github-ui/nested-list-view/NestedListItemLeadingVisual'
import {NestedListItemTitle} from '@github-ui/nested-list-view/NestedListItemTitle'
import {NestedListViewHeader} from '@github-ui/nested-list-view/NestedListViewHeader'
import {NestedListViewHeaderTitle} from '@github-ui/nested-list-view/NestedListViewHeaderTitle'
import {IssueDraftIcon, LinkIcon} from '@primer/octicons-react'
import {ActionList, Button, CounterLabel, SelectPanel} from '@primer/react'
import {useCallback, useMemo, useState} from 'react'

import type {TimelineEventTextReference} from '../../TimelineEvents'
import {type DraftIssue, getRevisionNumber, makeReferenceFromVersionedItem} from '../content-preview-types'
import {useContentPreview} from '../ContentPreviewContext'
import styles from './SubissuesList.module.css'
import {type TreeNode, useDraftIssueTreeMap, visit} from './use-draft-issue-tree-map'

// Values should be in sync with the server-side values found in packages/hierarchy/app/models/sub_issue.rb
const MAXIMUM_HEIGHT = 7
const MAXIMUM_BREADTH = 100

function useUnlinkSubIssueCallback() {
  const manager = useChatManager()
  const state = useChatState()
  const {updateItem} = useContentPreview()

  return useCallback(
    async (subIssue: DraftIssue) => {
      const instructions: TimelineEventTextReference = {
        type: 'text',
        name: `timeline-event: {"type": "unlink-sub-issue", "markdownContent": "Unlinked sub-issue '${subIssue.name}'"}`,
        text: `Unlink the sub issue '${subIssue.tag}' from its parent issue by removing the 'parentTag' field. Return the updated '${subIssue.tag}' draft-issue.`,
      }

      const updatedSubissue = {...subIssue, parentTag: undefined, isUserEdited: false}
      updateItem(updatedSubissue)

      const updatedSubIssueRef = makeReferenceFromVersionedItem(updatedSubissue)
      await manager.sendChatMessage({
        thread: getSelectedThread(state),
        content: 'Unlink the sub-issue from its parent issue',
        references: [instructions, updatedSubIssueRef],
        topic: state.currentTopic,
        context: state.context,
        customInstructions: state.customInstructions,
        model: state.model,
      })
    },
    [manager, state, updateItem],
  )
}

export function SubissuesList({issue}: {issue: DraftIssue}) {
  const {openItem, versionedItems} = useContentPreview()
  const treeNodes = useDraftIssueTreeMap()
  const onUnlinkSubIssue = useUnlinkSubIssueCallback()

  const currentNode = treeNodes.get(issue.tag)
  const childNodes = currentNode ? currentNode.children : []

  const totalChildCount = useMemo(() => {
    if (!currentNode) return 0

    let result = -1 // start at -1 to not count the current node itself
    visit(currentNode, () => result++)
    return result
  }, [currentNode])

  if (!copilotFeatureFlags.draftIssueTree) return null

  const renderTreeNode = (node: TreeNode<DraftIssue>) => {
    const version = getRevisionNumber(node.item.id, versionedItems)

    return (
      <NestedListItem
        key={node.item.tag}
        title={
          <NestedListItemTitle
            value={node.item.name}
            onClick={() => {
              openItem(node.item.id, true)
            }}
            trailingBadges={
              version != null ? [<VersionName key={`${node.item.tag}#${version}`} version={version} />] : undefined
            }
          />
        }
        secondaryActions={
          <NestedListItemActionBar
            actions={[]}
            staticMenuActions={[
              {
                key: 'unlink',
                render: () => {
                  return (
                    <ActionList.Item key={`${node.item.tag}-unlink`} onSelect={() => onUnlinkSubIssue(node.item)}>
                      <ActionList.LeadingVisual>
                        <LinkIcon />
                      </ActionList.LeadingVisual>
                      Unlink sub-issue
                    </ActionList.Item>
                  )
                },
              },
            ]}
          />
        }
        subItems={node.children?.length ? node.children.map(renderTreeNode) : undefined}
        defaultExpanded
      >
        <NestedListItemLeadingContent>
          <NestedListItemLeadingVisual>
            <IssueDraftIcon />
          </NestedListItemLeadingVisual>
        </NestedListItemLeadingContent>
      </NestedListItem>
    )
  }

  return (
    <div className="mt-2 border rounded-2">
      <NestedListView
        title="Sub-issues"
        header={
          <NestedListViewHeader
            title={
              <NestedListViewHeaderTitle title="Sub-issues" className="p-0">
                <CounterLabel>{totalChildCount}</CounterLabel>
              </NestedListViewHeaderTitle>
            }
            className="border-0 bgColor-default"
          />
        }
      >
        {childNodes.map(renderTreeNode)}
      </NestedListView>

      <LinkSubIssueButton issue={issue} />
    </div>
  )
}

function useLinkSubIssueCallback() {
  const manager = useChatManager()
  const state = useChatState()
  const {updateItem} = useContentPreview()

  return useCallback(
    async (parent: DraftIssue, subIssue: DraftIssue) => {
      const instructions: TimelineEventTextReference = {
        type: 'text',
        name: `timeline-event: {"type": "link-sub-issue", "markdownContent": "Linked sub-issue '${subIssue.name}'"}`,
        text: `Link the issue '${subIssue.tag}' as a child of '${parent.tag}' by setting the 'parentTag' field to '${parent.tag}'. Return the updated '${subIssue.tag}' draft-issue, along with its parent hierarchy.`,
      }

      const updatedSubissue = {...subIssue, parentTag: parent.tag, isUserEdited: false}
      updateItem(updatedSubissue)

      const updatedSubIssueRef = makeReferenceFromVersionedItem(updatedSubissue)
      await manager.sendChatMessage({
        thread: getSelectedThread(state),
        content: 'Link the sub-issue to its parent issue',
        references: [instructions, updatedSubIssueRef],
        topic: state.currentTopic,
        context: state.context,
        customInstructions: state.customInstructions,
        model: state.model,
      })
    },
    [manager, state, updateItem],
  )
}

function LinkSubIssueButton({issue}: {issue: DraftIssue}) {
  const {versionedItems} = useContentPreview()
  const treeNodes = useDraftIssueTreeMap()
  const onLinkSubIssue = useLinkSubIssueCallback()

  const issueNode = treeNodes.get(issue.tag)
  const reachedBreadthLimit = (issueNode?.children.length || 0) >= MAXIMUM_BREADTH

  const issueNodeLineage = useMemo(() => {
    const lineage = new Set<string>()
    let currentNode: TreeNode<DraftIssue> | null | undefined = issueNode
    while (currentNode) {
      lineage.add(currentNode.item.tag)
      currentNode = currentNode.parent
    }
    return lineage
  }, [issueNode])
  const currentNodeDepth = issueNodeLineage.size
  const reachedDepthLimit = currentNodeDepth >= MAXIMUM_HEIGHT

  const [open, setOpen] = useState<boolean>(false)

  const [textFilter, setTextFilter] = useState<string>('')
  const filteredItems = useMemo(() => {
    if (reachedBreadthLimit) {
      // limit overall tree width
      return []
    }

    if (reachedDepthLimit) {
      // limit overall tree height
      return []
    }

    return [...treeNodes.values()]
      .filter(node => !node.item.parentTag) // nodes that don't already have a parent
      .filter(node => !issueNodeLineage.has(node.item.tag)) // but not this node or any of its ancestors
      .filter(node => node.item.name.toLowerCase().includes(textFilter.toLowerCase())) // apply text filter
      .filter(node => {
        // Calculate the maximum tree depth of `node`
        // We already know `node` is a root node (no parent) per above filters.
        // For each element `n` in `node`s tree, we get the depth by counting the steps back up to the root.
        // The max depth of `node` is the maximum of all depths of its children.
        let nodeDepth = 0
        visit(node, n => {
          let depth = 1
          let current = n.parent
          while (current) {
            depth++
            current = current.parent
          }
          if (depth > nodeDepth) {
            nodeDepth = depth
          }
        })

        // limit overall tree depth
        return currentNodeDepth + nodeDepth <= MAXIMUM_HEIGHT
      })
      .map(node => ({
        id: node.item.tag,
        key: node.item.tag,
        text: node.item.name,
        leadingVisual: () => <IssueDraftIcon />,
        trailingVisual: () => {
          const version = getRevisionNumber(node.item.id, versionedItems)
          return !!version && <VersionName version={version} />
        },
        onAction: async () => {
          setOpen(false)
          await onLinkSubIssue(issue, node.item)
        },
      }))
  }, [
    reachedBreadthLimit,
    reachedDepthLimit,
    treeNodes,
    issueNodeLineage,
    textFilter,
    currentNodeDepth,
    versionedItems,
    onLinkSubIssue,
    issue,
  ])

  const blankslate = useMemo(() => {
    if (reachedBreadthLimit) {
      return {
        variant: 'warning' as const,
        title: 'Sub-issue limit reached',
        body: `Parents have a limit of ${MAXIMUM_BREADTH} sub-issues. To add more, an existing one must be removed.`,
      }
    }

    if (reachedDepthLimit) {
      return {
        variant: 'warning' as const,
        title: 'Sub-issue limit reached',
        body: `You can't add more than ${MAXIMUM_HEIGHT} layers of sub-issues. To add a sub-issue, remove a parent issue at any level.`,
      }
    }

    if (filteredItems.length === 0 && textFilter) {
      return {
        variant: 'empty' as const,
        title: 'No issues found',
        body: 'No issues match your search criteria.',
      }
    }

    if (filteredItems.length === 0 && !textFilter) {
      return {
        variant: 'empty' as const,
        title: 'No issues found',
        body: 'No issues available to link.',
      }
    }

    return undefined
  }, [reachedBreadthLimit, reachedDepthLimit, filteredItems.length, textFilter])

  return (
    <SelectPanel
      open={open}
      onOpenChange={setOpen}
      title="Select an issue"
      placeholder="Link sub-issue"
      placeholderText="Search"
      items={filteredItems}
      filterValue={textFilter}
      onFilterChange={setTextFilter}
      // The selected/onSelectedChange props are not used in this case, but required by SelectPanel
      selected={undefined}
      onSelectedChange={() => {}}
      overlayProps={{anchorSide: 'outside-right'}}
      className={styles.linkSubissueDialog}
      renderAnchor={({children, ...anchorProps}) => (
        <Button className="m-2" {...anchorProps} size="small">
          {children}
        </Button>
      )}
      message={blankslate}
    />
  )
}

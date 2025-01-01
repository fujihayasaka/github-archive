import {DragAndDrop} from '@github-ui/drag-and-drop'
import {IssueRow, IssuesIndexSecondaryGraphqlQuery} from '@github-ui/list-view-items-issues-prs/IssueRow'
import {PullRequestRow} from '@github-ui/list-view-items-issues-prs/PullRequestRow'
import {noop} from '@github-ui/noop'
import type {To, NavigateOptions} from 'react-router-dom'
import styles from './RepositoryMilestone.module.css'
import type {IssueRowSecondaryQuery} from '@github-ui/list-view-items-issues-prs/IssueRowSecondaryQuery'
import {IS_SERVER} from '@github-ui/ssr-utils'
import {useEffect} from 'react'
import {useQueryLoader} from 'react-relay'
import type {ItemNodeType} from './types'
import type {QUERY_FIELDS} from '@github-ui/list-view-items-issues-prs/Queries'
import {useNavigate} from '@github-ui/use-navigate'

type MilestoneIssuesListPageProps = {
  orderedNodes: ItemNodeType[]
  checkedItems: Map<string, ItemNodeType>
  itemSelected: (id: string, node: ItemNodeType, selected: boolean) => void
  getMetadataHref: (queryField: keyof typeof QUERY_FIELDS, metadataName: string) => string
  withDragAndDrop: boolean
  scopedRepository: {id: string; name: string; owner: string; is_archived: boolean}
  handleNavigate: (issueNumber: number, to: To, navOptions?: NavigateOptions) => Promise<void>
}

export function MilestoneIssuesListPage({
  orderedNodes,
  checkedItems,
  itemSelected,
  getMetadataHref,
  withDragAndDrop,
  scopedRepository,
  handleNavigate,
}: MilestoneIssuesListPageProps) {
  const navigate = useNavigate()
  const [milestoneIssuesLazyDataRef, loadMilestoneIssuesLazyData] = useQueryLoader<IssueRowSecondaryQuery>(
    IssuesIndexSecondaryGraphqlQuery,
  )
  const hasLazyData = milestoneIssuesLazyDataRef !== null
  useEffect(() => {
    if (!IS_SERVER) {
      const nodesIds = orderedNodes.map(node => node.id)
      loadMilestoneIssuesLazyData({nodes: nodesIds, includeReactions: false})
    }
  }, [loadMilestoneIssuesLazyData, orderedNodes, hasLazyData])

  const items = orderedNodes?.map((node, index) => {
    const sharedRowData = {
      key: node.id,
      isActive: false,
      isSelected: node && checkedItems.has(node.id),
      onSelect: (selected: boolean) => node && itemSelected(node.id, node, selected),
      onSelectRow: noop,
      getMetadataHref,
      reactionEmojiToDisplay: {reaction: '', reactionEmoji: ''},
      sortingItemSelected: '',
      scopedRepository,
      metadataRef: milestoneIssuesLazyDataRef,
    }
    if (!withDragAndDrop) {
      if (node.__typename === 'Issue') {
        return (
          <IssueRow
            issueKey={node}
            onNavigate={(to: To, navOptions?: NavigateOptions) => handleNavigate(node.number, to, navOptions)}
            {...sharedRowData}
            key={sharedRowData.key}
          />
        )
      } else {
        return (
          <PullRequestRow
            pullRequestKey={node}
            includeGitDataFromMainQuery={false}
            onNavigate={navigate}
            {...sharedRowData}
            key={sharedRowData.key}
          />
        )
      }
    }

    return (
      <DragAndDrop.Item
        hideSortableItemTrigger
        as="li"
        index={index}
        id={node.id}
        key={node.id}
        title={''}
        style={{display: 'flex', width: '100%'}}
        className={styles.dragAndDropItem}
      >
        {node.__typename === 'Issue' ? (
          <IssueRow
            issueKey={node}
            onNavigate={(to: To, navOptions?: NavigateOptions) => handleNavigate(node.number, to, navOptions)}
            {...sharedRowData}
            key={sharedRowData.key}
            as="div"
            role="none"
          />
        ) : (
          <PullRequestRow
            pullRequestKey={node}
            includeGitDataFromMainQuery={false}
            onNavigate={navigate}
            {...sharedRowData}
            key={sharedRowData.key}
            as="div"
            role="none"
          />
        )}
      </DragAndDrop.Item>
    )
  })
  return <>{items}</>
}

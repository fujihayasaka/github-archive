import {useMemo, type ReactElement} from 'react'
import {useFragment, useRefetchableFragment} from 'react-relay'
import {graphql} from 'relay-runtime'
import {NestedListItem} from '@github-ui/nested-list-view/NestedListItem'
import {NestedListItemMetadata} from '@github-ui/nested-list-view/NestedListItemMetadata'
import {AvatarStack, Link} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {NestedListItemLeadingContent} from '@github-ui/nested-list-view/NestedListItemLeadingContent'
import {PersonIcon, CircleIcon} from '@primer/octicons-react'
import {userHovercardPath} from '@github-ui/paths'
import {ClosedByPullRequestsReferences} from '@github-ui/list-view-items-issues-prs/ClosedByPullRequestsReferences'

import {SubIssuesActionBar} from './SubIssuesActionBar'
import {getIssueSearchURL} from '../utils/urls'
import {SubIssueStateIcon} from './SubIssueStateIcon'

import styles from './SubIssuesListItem.module.css'

import type {SubIssuesListItem$key} from './__generated__/SubIssuesListItem.graphql'
import type {SubIssuesListItem_NestedSubIssues$key} from './__generated__/SubIssuesListItem_NestedSubIssues.graphql'
import type {SubIssuesListItem_NestedSubIssuesQuery} from './__generated__/SubIssuesListItem_NestedSubIssuesQuery.graphql'
import {useSubIssueSubscription} from '../subscriptions/sub-issue-subscription'
import {SubIssueTitle} from './SubIssueTitle'
import type {SubIssueSidePanelItem} from '../types/sub-issue-types'

const SubIssuesListItem_NestedSubIssues = graphql`
  fragment SubIssuesListItem_NestedSubIssues on Issue
  @refetchable(queryName: "SubIssuesListItem_NestedSubIssuesQuery")
  @argumentDefinitions(fetchSubIssues: {type: "Boolean", defaultValue: false}) {
    ...SubIssueTitle @arguments(fetchSubIssues: $fetchSubIssues)
    subIssuesSummary @skip(if: $fetchSubIssues) {
      total
    }
    # subIssueConnection.totalCount still queries all sub-issues for an issue, so we should use subIssuesSummary.total
    # unless we're specifically fetching sub-issues.
    subIssuesConnection: subIssues @include(if: $fetchSubIssues) {
      totalCount
    }
    subIssues(first: 100) @include(if: $fetchSubIssues) {
      nodes {
        id
        ...SubIssuesListItem
      }
    }
  }
`

const SubIssuesListItemFragment = graphql`
  fragment SubIssuesListItem on Issue {
    id
    ...SubIssueStateIcon
    assignees(first: 10) {
      totalCount
      edges {
        node {
          id
          login
          avatarUrl
        }
      }
    }
    url
    repository {
      name
      owner {
        login
      }
    }
    ...SubIssuesListItem_NestedSubIssues @arguments(fetchSubIssues: false)
    ...ClosedByPullRequestsReferences
  }
`

export function SubIssuesListItem({
  parentIssueId,
  parentRepoName,
  issueKey,
  onSubIssueClick,
  // Temporary prop to control drag-ability of items. Used for M1 when we can only drag first level items
  // Will be removed in M2 when dnd is enabled for all the items.
  dnd = false,
  isDragOverlay = false,
  readonly = false,
}: {
  parentIssueId: string
  issueKey: SubIssuesListItem$key
  parentRepoName?: string
  onSubIssueClick?: (subIssueItem: SubIssueSidePanelItem) => void
  dnd?: boolean
  isDragOverlay?: boolean
  readonly?: boolean
}) {
  const issueNode = useFragment(SubIssuesListItemFragment, issueKey)

  const [subIssuesData, refetch] = useRefetchableFragment<
    SubIssuesListItem_NestedSubIssuesQuery,
    SubIssuesListItem_NestedSubIssues$key
  >(SubIssuesListItem_NestedSubIssues, issueNode)
  const subItems = useMemo(() => {
    const elements = subIssuesData?.subIssues?.nodes?.reduce(
      (arr, subIssueNode) => {
        if (subIssueNode) {
          arr.push(
            <SubIssuesListItem
              key={subIssueNode.id}
              issueKey={subIssueNode}
              parentRepoName={parentRepoName}
              parentIssueId={issueNode.id}
              onSubIssueClick={onSubIssueClick}
              readonly={readonly}
            />,
          )
        }
        return arr
      },
      [] as Array<ReactElement<typeof NestedListItem>>,
    )
    if (!elements || elements.length === 0) return undefined
    return elements
  }, [issueNode.id, onSubIssueClick, readonly, subIssuesData?.subIssues?.nodes, parentRepoName])

  // subItems will be undefined until the subIssues have been loaded, at which point we want to start keeping track of them for live updates
  useSubIssueSubscription(issueNode.id, {fetchSubIssues: subItems !== undefined})

  const subItemsCount = subIssuesData.subIssuesConnection?.totalCount || subIssuesData.subIssuesSummary?.total || 0

  if (!issueNode) return null
  return (
    <NestedListItem
      key={issueNode.id}
      className={styles.metadataContainer}
      metadataContainerClassName={styles.itemMetadataContainer}
      dragAndDropProps={{
        isOverlay: isDragOverlay,
        showTrigger: dnd,
        itemId: issueNode.id,
      }}
      title={<SubIssueTitle issueKey={subIssuesData} onClick={onSubIssueClick} parentRepoName={parentRepoName} />}
      secondaryActions={
        readonly ? undefined : (
          <SubIssuesActionBar issueId={parentIssueId} subIssueId={issueNode.id} subIssueUrl={issueNode.url} />
        )
      }
      metadata={
        <NestedListItemMetadata alignment="right" className={styles.NestedListItemMetadata_0}>
          <div className={styles.Box_0}>
            <ClosedByPullRequestsReferences issueId={issueNode.id} closedByPullRequestsReferencesKey={issueNode} />
          </div>
          <div className={styles.Box_1}>
            {issueNode.assignees.totalCount === 0 ? (
              <div className={styles.Box_2}>
                <Octicon icon={PersonIcon} className={styles.Octicon_0} />
                <Octicon size={24} icon={CircleIcon} className={styles.Octicon_1} />
              </div>
            ) : (
              <AvatarStack alignRight>
                {issueNode.assignees.edges?.map(assigneeEdge => {
                  if (!assigneeEdge?.node) return null
                  return (
                    <Link
                      key={assigneeEdge.node.id}
                      href={getIssueSearchURL(
                        {owner: issueNode.repository.owner.login, repo: issueNode.repository.name},
                        'assignee',
                        assigneeEdge.node.login,
                      )}
                      data-hovercard-url={userHovercardPath({owner: assigneeEdge.node.login})}
                      className={styles.Link_0}
                    >
                      <GitHubAvatar
                        key={assigneeEdge.node.id}
                        alt={assigneeEdge.node.login}
                        src={assigneeEdge.node.avatarUrl}
                      />
                    </Link>
                  )
                })}
              </AvatarStack>
            )}
          </div>
        </NestedListItemMetadata>
      }
      subItemsCount={subItemsCount}
      loadSubItems={async () => {
        refetch({fetchSubIssues: true})
      }}
      subItems={subItems}
    >
      <NestedListItemLeadingContent>
        <SubIssueStateIcon dataKey={issueNode} />
      </NestedListItemLeadingContent>
    </NestedListItem>
  )
}

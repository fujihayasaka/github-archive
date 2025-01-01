import {GitHubAvatar} from '@github-ui/github-avatar'
import {NestedListView} from '@github-ui/nested-list-view'
import {NestedListItem} from '@github-ui/nested-list-view/NestedListItem'
import {NestedListItemActionBar} from '@github-ui/nested-list-view/NestedListItemActionBar'
import {NestedListItemLeadingContent} from '@github-ui/nested-list-view/NestedListItemLeadingContent'
import {NestedListItemLeadingVisual} from '@github-ui/nested-list-view/NestedListItemLeadingVisual'
import {NestedListItemMetadata} from '@github-ui/nested-list-view/NestedListItemMetadata'
import {NestedListItemTitle} from '@github-ui/nested-list-view/NestedListItemTitle'
import {NestedListItemTrailingBadge} from '@github-ui/nested-list-view/NestedListItemTrailingBadge'
import {NestedListViewCompletionPill} from '@github-ui/nested-list-view/NestedListViewCompletionPill'
import {NestedListViewHeader} from '@github-ui/nested-list-view/NestedListViewHeader'
import {NestedListViewHeaderTitle} from '@github-ui/nested-list-view/NestedListViewHeaderTitle'
import {CircleIcon, GitPullRequestIcon, IssueClosedIcon, IssueOpenedIcon, PersonIcon} from '@primer/octicons-react'
import {ActionList, AvatarStack, IssueLabelToken} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {fetchQuery, graphql, useFragment, useRelayEnvironment} from 'react-relay'
import {createOperationDescriptor, getRequest} from 'relay-runtime'
import type RelayModernEnvironment from 'relay-runtime/lib/store/RelayModernEnvironment'

import type {IssueSubIssues_InnerFragment$key} from './__generated__/IssueSubIssues_InnerFragment.graphql'
import type {IssueSubIssues_NestedQuery} from './__generated__/IssueSubIssues_NestedQuery.graphql'
import type {IssueSubIssues_SandboxFragment$key} from './__generated__/IssueSubIssues_SandboxFragment.graphql'
import styles from './IssueSubIssues.module.css'

const IssueSubIssues_InnerFragment = graphql`
  fragment IssueSubIssues_InnerFragment on Issue {
    id
    title
    titleHTML
    state
    url
    labels(first: 10) {
      nodes {
        id
        name
        color
      }
    }
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
    subIssuesSummary {
      total
      completed
      percentCompleted
    }
    closedByPullRequestsReferences(first: 0, includeClosedPrs: true) {
      totalCount
    }
  }
`

const IssueSubIssues_SandboxFragment = graphql`
  fragment IssueSubIssues_SandboxFragment on Issue {
    id
    subIssues(first: 100) {
      nodes {
        id
        ...IssueSubIssues_InnerFragment
      }
    }
    subIssuesSummary {
      total
      completed
      percentCompleted
    }
  }
`

const subIssuesNestedQuery = graphql`
  query IssueSubIssues_NestedQuery($id: ID!) {
    node(id: $id) {
      ... on Issue {
        id
        subIssues(first: 100) {
          nodes {
            ...IssueSubIssues_InnerFragment
          }
        }
      }
    }
  }
`

export function IssueSubIssues({issueKey}: {issueKey: IssueSubIssues_SandboxFragment$key}) {
  const data = useFragment(IssueSubIssues_SandboxFragment, issueKey)

  const {total, completed, percentCompleted} = data.subIssuesSummary

  return (
    <NestedListView
      title="Sub-issues"
      header={
        <NestedListViewHeader
          title={<NestedListViewHeaderTitle title="Sub issues" />}
          className={styles.container}
          completionPill={
            <NestedListViewCompletionPill
              progress={{
                total,
                completed,
                percentCompleted,
              }}
            />
          }
        />
      }
      isCollapsible
    >
      {data.subIssues.nodes?.map(node => {
        if (!node) return null
        return <SubIssuesNestedListItem key={node.id} subIssueKey={node} />
      })}
    </NestedListView>
  )
}

const fetchSubIssues = (environment: RelayModernEnvironment, issueId: string) => {
  const queryRequest = getRequest(subIssuesNestedQuery)
  const queryDescriptor = createOperationDescriptor(queryRequest, {})
  environment.retain(queryDescriptor)

  return fetchQuery<IssueSubIssues_NestedQuery>(
    environment,
    subIssuesNestedQuery,
    {id: issueId},
    {fetchPolicy: 'store-or-network'},
  ).toPromise()
}

const SubIssuesNestedListItem = ({subIssueKey}: {subIssueKey: IssueSubIssues_InnerFragment$key}) => {
  const issueNode = useFragment(IssueSubIssues_InnerFragment, subIssueKey)
  const environment = useRelayEnvironment()

  if (!issueNode) return null

  const filteredLabels = issueNode.labels?.nodes?.filter(label => label !== null && label !== undefined) || []
  const trailingBadges =
    filteredLabels.map(label => {
      return (
        <NestedListItemTrailingBadge key={label.id} title={label.name}>
          <IssueLabelToken text={label.name} fillColor={`#${label.color}`} />
        </NestedListItemTrailingBadge>
      )
    }) || []

  const {total, completed, percentCompleted} = issueNode.subIssuesSummary

  const completionMetadata = (
    <NestedListItemTrailingBadge key={filteredLabels.length} title="Sub-issues">
      <NestedListViewCompletionPill
        progress={{
          total,
          completed,
          percentCompleted,
        }}
        href={issueNode.url}
      />
    </NestedListItemTrailingBadge>
  )

  if (total > 0) trailingBadges.unshift(completionMetadata)

  const subItemsCount = issueNode.subIssuesSummary.total

  return (
    <NestedListItem
      key={issueNode.id}
      title={
        <NestedListItemTitle
          value={issueNode.titleHTML || issueNode.title}
          href={issueNode.url}
          trailingBadges={trailingBadges}
        />
      }
      subItemsCount={subItemsCount}
      loadSubItems={async () => {
        const data = await fetchSubIssues(environment, issueNode.id)
        if (!data) return []

        const elements = data?.node?.subIssues?.nodes?.map((node, index) => {
          // eslint-disable-next-line @eslint-react/no-array-index-key
          return <SubIssuesNestedListItem key={index} subIssueKey={node!} />
        })

        if (!elements) return []

        return elements
      }}
      metadata={
        <NestedListItemMetadata className={styles.NestedListItemMetadata_0}>
          <div className={styles.Box_0}>
            {issueNode.closedByPullRequestsReferences?.totalCount ?? 0 > 0 ? (
              <>
                <GitPullRequestIcon />
                {issueNode.closedByPullRequestsReferences?.totalCount}
              </>
            ) : null}
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
                    <GitHubAvatar
                      key={assigneeEdge.node.id}
                      alt={assigneeEdge.node.login}
                      src={assigneeEdge.node.avatarUrl}
                    />
                  )
                })}
              </AvatarStack>
            )}
          </div>
        </NestedListItemMetadata>
      }
      secondaryActions={
        <NestedListItemActionBar
          label="action-bar"
          staticMenuActions={[
            {
              key: 'secondaryActionItem',
              render: () => <ActionList.Item>Secondary Action Item</ActionList.Item>,
            },
          ]}
        />
      }
    >
      <NestedListItemLeadingContent>
        <NestedListItemLeadingVisual
          icon={issueNode.state === 'CLOSED' ? IssueClosedIcon : IssueOpenedIcon}
          color={issueNode.state === 'CLOSED' ? 'var(--fgColor-done)' : 'var(--fgColor-open)'}
        />
      </NestedListItemLeadingContent>
    </NestedListItem>
  )
}

import type {PropsWithChildren} from 'react'
import {graphql, useFragment} from 'react-relay'
import {AvatarStack, Button, Link} from '@primer/react'
import {PersonIcon, CircleIcon} from '@primer/octicons-react'
import {userHovercardPath} from '@github-ui/paths'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {useIssueState} from '@github-ui/use-issue-state'
import {ListView} from '@github-ui/list-view'
import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListItemLeadingVisual} from '@github-ui/list-view/ListItemLeadingVisual'
import {ListItemDescription} from '@github-ui/list-view/ListItemDescription'
import {ClosedByPullRequestsReferences} from '@github-ui/list-view-items-issues-prs/ClosedByPullRequestsReferences'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {ListItemMetadata} from '@github-ui/list-view/ListItemMetadata'
import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {getIssueTitle, getIssueSearchURL} from '../../../utils/helpers'
import {testIdProps} from '@github-ui/test-id-props'
import {LABELS} from '../../../constants/labels'
import styles from './PaginatedRelationshipsListAllView.module.css'
import type {
  PaginatedRelationshipsListAllViewItemFragment$data,
  PaginatedRelationshipsListAllViewItemFragment$key,
} from './__generated__/PaginatedRelationshipsListAllViewItemFragment.graphql'

export const TEST_ID_SKELETON_ITEM = '__test-paginated-relationships-list-item-skeleton'
export const TEST_ID_PULL_REQUEST_METADATA = '__test-relationships-list-all-view-pull-request-metadata'

export const PAGE_SIZE = 25
const SKELETON_ROWS = 3

export const PaginatedRelationshipsListAllViewItemFragment = graphql`
  fragment PaginatedRelationshipsListAllViewItemFragment on Issue {
    id
    url
    number
    title
    titleHTML
    state
    stateReason
    repository {
      name
      nameWithOwner
      owner {
        login
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
    ...ClosedByPullRequestsReferences
  }
`

type RelationshipsListAllViewPaginatedProps = PropsWithChildren<{
  accessibleTitle: string
  isLoadingNext: boolean
  hasNextPage: boolean
  onLoadMore: () => void
}>
export function RelationshipsListAllViewPaginated({
  accessibleTitle,
  isLoadingNext,
  hasNextPage,
  onLoadMore,
  children,
}: RelationshipsListAllViewPaginatedProps) {
  const loadingSkeletonItems = []
  if (isLoadingNext) {
    for (let i = 0; i < SKELETON_ROWS; i += 1) {
      loadingSkeletonItems.push(<RelationshipListItemSkeleton key={i} />)
    }
  }

  return (
    <>
      <ListView title={accessibleTitle} variant="compact">
        {children}
        {isLoadingNext && loadingSkeletonItems}
      </ListView>
      {hasNextPage && (
        <div className={styles.PaginatedRelationshipsListAllView_ControlWrapper}>
          <Button onClick={onLoadMore} disabled={isLoadingNext}>
            {LABELS.loadMoreItems}
          </Button>
        </div>
      )}
    </>
  )
}

type RelationshipsListItemProps = {
  issueFragment: PaginatedRelationshipsListAllViewItemFragment$key
  sourceIssueRepositoryNameWithOwner?: string
}
export function RelationshipsListItem({issueFragment, sourceIssueRepositoryNameWithOwner}: RelationshipsListItemProps) {
  const issue = useFragment(PaginatedRelationshipsListAllViewItemFragment, issueFragment)

  const {sourceIcon} = useIssueState({
    state: issue.state,
    stateReason: issue.stateReason,
  })
  const IconComponent = sourceIcon('Issue')

  const canonicalIssueReference = getCanonicalIssueReference(
    sourceIssueRepositoryNameWithOwner,
    issue.repository.nameWithOwner,
    issue.number,
  )

  return (
    <ListItem
      title={<RelationshipsListItemTitle issue={issue} />}
      metadata={<RelationshipsListItemMetadata issue={issue} />}
    >
      <ListItemLeadingContent>
        <ListItemLeadingVisual icon={IconComponent} />
      </ListItemLeadingContent>

      <ListItemMainContent>
        <ListItemDescription>{canonicalIssueReference}</ListItemDescription>
      </ListItemMainContent>
    </ListItem>
  )
}

export function RelationshipsListViewLoadingSkeleton() {
  const rows = []
  for (let i = 0; i < SKELETON_ROWS; i += 1) {
    rows.push(<RelationshipListItemSkeleton key={i} />)
  }
  return (
    <>
      <ListView title={LABELS.relationLoadingList} variant="compact">
        {rows}
      </ListView>
    </>
  )
}

type RelationshipsListItemTitleProps = {
  issue: {title: string; titleHTML: string; url: string}
}
function RelationshipsListItemTitle({issue}: RelationshipsListItemTitleProps) {
  const titleValue = getIssueTitle(issue.title, issue.titleHTML)
  return <ListItemTitle value={titleValue} href={issue.url} anchorClassName="markdown-title" />
}

type RelationshipsListItemMetadataProps = {
  issue: PaginatedRelationshipsListAllViewItemFragment$data
}
function RelationshipsListItemMetadata({issue}: RelationshipsListItemMetadataProps) {
  return (
    <>
      <ListItemMetadata {...testIdProps(TEST_ID_PULL_REQUEST_METADATA)}>
        <ClosedByPullRequestsReferences issueId={issue.id} closedByPullRequestsReferencesKey={issue} />
      </ListItemMetadata>
      <ListItemMetadata>
        <RelationshipsListItemAvatarMetadata
          owner={issue.repository.owner.login}
          repo={issue.repository.name}
          assignees={issue.assignees}
        />
      </ListItemMetadata>
    </>
  )
}

type RelationshipsListItemAvatarMetadataProps = {
  owner: string
  repo: string
  assignees: PaginatedRelationshipsListAllViewItemFragment$data['assignees']
}
function RelationshipsListItemAvatarMetadata({owner, repo, assignees}: RelationshipsListItemAvatarMetadataProps) {
  const edges = assignees.edges

  if (assignees.totalCount === 0 || !edges) return <EmptyAvatar />

  const assigneeNodes = edges.map(edge => edge?.node).filter(node => !!node)

  return (
    <AvatarStack alignRight className={styles.PaginatedRelationshipsListAllView_AvatarArea}>
      {assigneeNodes.map(assignee => (
        <Link
          key={assignee.id}
          href={getIssueSearchURL({owner, repo}, 'assignee', assignee.login)}
          data-hovercard-url={userHovercardPath({owner: assignee.login})}
          data-hovercard-fixed-positioning
          className={styles.PaginatedRelationshipsListAllView_AvatarLink}
        >
          <GitHubAvatar alt={assignee.login} src={assignee.avatarUrl} />
        </Link>
      ))}
    </AvatarStack>
  )
}

function EmptyAvatar() {
  return (
    <div className={styles.PaginatedRelationshipsListAllView_EmptyAvatar}>
      <PersonIcon size={16} />
      <CircleIcon size={24} />
    </div>
  )
}

function RelationshipListItemSkeleton() {
  return (
    <ListItem
      {...testIdProps(TEST_ID_SKELETON_ITEM)}
      title={
        <ListItemTitle value={''}>
          <LoadingSkeleton height="20px" width="30ch" />
        </ListItemTitle>
      }
      metadata={
        <>
          <ListItemMetadata>
            <LoadingSkeleton variant="rounded" width="4ch" />
          </ListItemMetadata>
          <ListItemMetadata>
            <LoadingSkeleton variant="elliptical" width="20px" height="20px" />
          </ListItemMetadata>
        </>
      }
    />
  )
}

const getCanonicalIssueReference = (
  sourceIssueRepositoryNameWithOwner: string = '',
  targetIssueRepositoryNameWithOwner: string,
  issueNumber: number,
) => {
  const isSameRepositoryAsOwnerIssue =
    !sourceIssueRepositoryNameWithOwner || sourceIssueRepositoryNameWithOwner === targetIssueRepositoryNameWithOwner
  return `${isSameRepositoryAsOwnerIssue ? '' : targetIssueRepositoryNameWithOwner}#${issueNumber}`
}

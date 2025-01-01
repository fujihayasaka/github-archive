import {Suspense, useCallback} from 'react'
import {useLazyLoadQuery, usePaginationFragment} from 'react-relay'
import {graphql} from 'relay-runtime'
import {Banner} from '@primer/react/experimental'
import {
  PAGE_SIZE,
  RelationshipsListAllViewPaginated,
  RelationshipsListItem,
  RelationshipsListViewLoadingSkeleton,
} from './PaginatedRelationshipsListAllView'
import type {LazyRelationshipsBlockedByListViewQuery} from './__generated__/LazyRelationshipsBlockedByListViewQuery.graphql'
import {LABELS} from '../../../constants/labels'
import type {LazyRelationshipsBlockedByListViewFragment$data} from './__generated__/LazyRelationshipsBlockedByListViewFragment.graphql'
import {ActionList} from '@primer/react'
import {LockIcon} from '@primer/octicons-react'

// this connection string has to match the @connection string defined in the query below
export const BLOCKED_BY_LIST_ALL_RELAY_CONNECTION = 'LazyRelationshipsBlockedByListViewFragment__blockedBy'

export const LazyRelationshipsBlockedByListViewFragment = graphql`
  fragment LazyRelationshipsBlockedByListViewFragment on Issue
  @refetchable(queryName: "LazyRelationshipsBlockedByListViewPaginatedQuery")
  @argumentDefinitions(cursor: {type: "String", defaultValue: null}, pageSize: {type: "Int"}) {
    repository {
      nameWithOwner
    }
    blockedBy(first: $pageSize, after: $cursor)
      @connection(key: "LazyRelationshipsBlockedByListViewFragment__blockedBy") {
      edges {
        node {
          id
          ...PaginatedRelationshipsListAllViewItemFragment
        }
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
`

export const LazyRelationshipsBlockedByListViewQueryGraphQL = graphql`
  query LazyRelationshipsBlockedByListViewQuery($id: ID!, $cursor: String, $pageSize: Int) {
    issue: node(id: $id) {
      ...LazyRelationshipsBlockedByListViewFragment @arguments(cursor: $cursor, pageSize: $pageSize)
    }
  }
`

export type LazyRelationshipsBlockedByListViewProps = {
  itemId: string
  pageSize?: number
  blockedByCount: number
}
export function LazyRelationshipsBlockedByListView({
  itemId,
  pageSize = PAGE_SIZE,
  blockedByCount,
}: LazyRelationshipsBlockedByListViewProps) {
  const loadingSkeletonComponent = <RelationshipsListViewLoadingSkeleton />

  return (
    <Suspense fallback={loadingSkeletonComponent}>
      <RelationshipsBlockedByListViewInternal itemId={itemId} pageSize={pageSize} blockedByCount={blockedByCount} />
    </Suspense>
  )
}

type RelationshipsBlockedByListViewProps = {
  itemId: string
  pageSize: number
  blockedByCount: number
}
function RelationshipsBlockedByListViewInternal({
  itemId,
  pageSize,
  blockedByCount,
}: RelationshipsBlockedByListViewProps) {
  const queryData = useLazyLoadQuery<LazyRelationshipsBlockedByListViewQuery>(
    LazyRelationshipsBlockedByListViewQueryGraphQL,
    {id: itemId, pageSize},
  )

  const issueFragment = queryData.issue
  const {data, loadNext, isLoadingNext} = usePaginationFragment(
    LazyRelationshipsBlockedByListViewFragment,
    issueFragment,
  )
  const issueData = data as LazyRelationshipsBlockedByListViewFragment$data | null
  const onLoadMore = useCallback(() => loadNext(PAGE_SIZE), [loadNext])

  const emptyBanner = (
    <Banner variant="info">
      <Banner.Title>{LABELS.emptyBlockedByList}</Banner.Title>
    </Banner>
  )

  if (!issueFragment || !issueData) return emptyBanner

  const repository = issueData.repository
  if (!repository) return emptyBanner

  const edges = issueData.blockedBy?.edges?.filter(edge => edge && edge.node)
  if (!edges || edges.length === 0) return emptyBanner

  // There is a PAGE_SIZE pagination limit for edges. If we have fewer visible edges than the total count,
  // and we've reached the last page (no next page available), then we can conclude that some issues
  // are inaccessible due to privacy restrictions.
  const isLastPage = !issueData.blockedBy?.pageInfo?.hasNextPage
  const hasInaccessibleBlockedByIssues = edges.length < blockedByCount && isLastPage

  return (
    <RelationshipsListAllViewPaginated
      accessibleTitle={LABELS.relationNames.blockedByIssues}
      isLoadingNext={isLoadingNext}
      hasNextPage={issueData.blockedBy?.pageInfo?.hasNextPage}
      onLoadMore={onLoadMore}
    >
      {edges.map(edge => (
        <RelationshipsListItem
          key={edge!.node!.id}
          issueFragment={edge!.node!}
          sourceIssueRepositoryNameWithOwner={repository.nameWithOwner}
        />
      ))}
      {hasInaccessibleBlockedByIssues && (
        <ActionList.Item disabled aria-disabled="true" className="pl-3">
          <ActionList.LeadingVisual>
            <LockIcon size={16} />
          </ActionList.LeadingVisual>
          <span className="text-small color-fg-muted" data-testid="private-blocked-by-notice-modal">
            Private issues are hidden.
          </span>
        </ActionList.Item>
      )}
    </RelationshipsListAllViewPaginated>
  )
}

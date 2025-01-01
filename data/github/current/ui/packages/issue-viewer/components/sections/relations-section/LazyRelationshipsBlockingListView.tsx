import {Suspense, useCallback} from 'react'
import {useLazyLoadQuery, usePaginationFragment} from 'react-relay'
import {graphql} from 'relay-runtime'
import {Banner} from '@primer/react/experimental'
import {ActionList} from '@primer/react'
import {LockIcon} from '@primer/octicons-react'
import {
  PAGE_SIZE,
  RelationshipsListAllViewPaginated,
  RelationshipsListItem,
  RelationshipsListViewLoadingSkeleton,
} from './PaginatedRelationshipsListAllView'
import type {LazyRelationshipsBlockingListViewQuery} from './__generated__/LazyRelationshipsBlockingListViewQuery.graphql'
import {LABELS} from '../../../constants/labels'
import type {LazyRelationshipsBlockingListViewFragment$data} from './__generated__/LazyRelationshipsBlockingListViewFragment.graphql'

// this connection string has to match the @connection string defined in the query below
export const BLOCKING_LIST_ALL_RELAY_CONNECTION = 'LazyRelationshipsBlockingListViewFragment__blocking'

export const LazyRelationshipsBlockingListViewFragment = graphql`
  fragment LazyRelationshipsBlockingListViewFragment on Issue
  @refetchable(queryName: "LazyRelationshipsBlockingListViewPaginatedQuery")
  @argumentDefinitions(cursor: {type: "String", defaultValue: null}, pageSize: {type: "Int"}) {
    repository {
      nameWithOwner
    }
    blocking(first: $pageSize, after: $cursor) @connection(key: "LazyRelationshipsBlockingListViewFragment__blocking") {
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

export const LazyRelationshipsBlockingListViewQueryGraphQL = graphql`
  query LazyRelationshipsBlockingListViewQuery($id: ID!, $cursor: String, $pageSize: Int) {
    issue: node(id: $id) {
      ...LazyRelationshipsBlockingListViewFragment @arguments(cursor: $cursor, pageSize: $pageSize)
    }
  }
`

export type LazyRelationshipsBlockingListViewProps = {
  itemId: string
  pageSize?: number
  blockingCount: number
}
export function LazyRelationshipsBlockingListView({
  itemId,
  pageSize = PAGE_SIZE,
  blockingCount,
}: LazyRelationshipsBlockingListViewProps) {
  const loadingSkeletonComponent = <RelationshipsListViewLoadingSkeleton />

  return (
    <Suspense fallback={loadingSkeletonComponent}>
      <RelationshipsBlockingListViewInternal itemId={itemId} pageSize={pageSize} blockingCount={blockingCount} />
    </Suspense>
  )
}

type RelationshipsBlockingListViewProps = {
  itemId: string
  pageSize: number
  blockingCount: number
}
function RelationshipsBlockingListViewInternal({itemId, pageSize, blockingCount}: RelationshipsBlockingListViewProps) {
  const queryData = useLazyLoadQuery<LazyRelationshipsBlockingListViewQuery>(
    LazyRelationshipsBlockingListViewQueryGraphQL,
    {id: itemId, pageSize},
  )

  const issueFragment = queryData.issue
  const {data, loadNext, isLoadingNext} = usePaginationFragment(
    LazyRelationshipsBlockingListViewFragment,
    issueFragment,
  )
  const issueData = data as LazyRelationshipsBlockingListViewFragment$data | null
  const onLoadMore = useCallback(() => loadNext(PAGE_SIZE), [loadNext])

  const emptyBanner = (
    <Banner variant="info">
      <Banner.Title>{LABELS.emptyBlockingList}</Banner.Title>
    </Banner>
  )

  if (!issueFragment || !issueData) return emptyBanner

  const repository = issueData.repository
  if (!repository) return emptyBanner

  const edges = issueData.blocking?.edges?.filter(edge => edge && edge.node)
  if (!edges || edges.length === 0) return emptyBanner

  // There is a PAGE_SIZE pagination limit for edges. If we have fewer visible edges than the total count,
  // and we've reached the last page (no next page available), then we can conclude that some issues
  // are inaccessible due to privacy restrictions.
  const isLastPage = !issueData.blocking?.pageInfo?.hasNextPage
  const hasInaccessibleBlockingIssues = edges.length < blockingCount && isLastPage

  return (
    <RelationshipsListAllViewPaginated
      accessibleTitle={LABELS.relationNames.blockingIssues}
      isLoadingNext={isLoadingNext}
      hasNextPage={issueData.blocking?.pageInfo?.hasNextPage}
      onLoadMore={onLoadMore}
    >
      {edges.map(edge => (
        <RelationshipsListItem
          key={edge!.node!.id}
          issueFragment={edge!.node!}
          sourceIssueRepositoryNameWithOwner={repository.nameWithOwner}
        />
      ))}
      {hasInaccessibleBlockingIssues && (
        <ActionList.Item disabled aria-disabled="true" className="pl-3">
          <ActionList.LeadingVisual>
            <LockIcon size={16} />
          </ActionList.LeadingVisual>
          <span className="text-small color-fg-muted" data-testid="private-blocking-notice-modal">
            Private issues are hidden.
          </span>
        </ActionList.Item>
      )}
    </RelationshipsListAllViewPaginated>
  )
}

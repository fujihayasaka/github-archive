import {ListView} from '@github-ui/list-view'
import {testIdProps} from '@github-ui/test-id-props'
import {graphql, usePaginationFragment, useQueryLoader, type LoadMoreFn} from 'react-relay'
import styles from './RepositoryLabel.module.css'
import {useEffect, useMemo} from 'react'
import type {LabelList$data, LabelList$key} from './__generated__/LabelList.graphql'
import type {OperationType} from 'relay-runtime'
import {LabelRow} from './LabelRow'
import {LabelSortMenu} from './LabelSortMenu'
import {ListViewMetadata} from '@github-ui/list-view/ListViewMetadata'
import {LabelListPagination} from './LabelListPagination'
import {EmptyState} from './EmptyState'
import {IS_SERVER} from '@github-ui/ssr-utils'
import {IssuesAndPullRequestsCountSecondaryQueryQ} from './IssuesAndPullRequestsCount'
import type {IssuesAndPullRequestsCountSecondaryQuery} from './__generated__/IssuesAndPullRequestsCountSecondaryQuery.graphql'
import {useSearchParams} from '@github-ui/use-navigate'

type LabelListProps = {
  repositoryRef: LabelList$key
  onCreateLabel?: () => void
}

export function LabelList({repositoryRef, onCreateLabel}: LabelListProps) {
  const {data, loadNext, hasNext} = usePaginationFragment(
    graphql`
      fragment LabelList on Repository
      @refetchable(queryName: "LabelListQuery")
      @argumentDefinitions(
        cursor: {type: "String", defaultValue: null}
        first: {type: "Int!"}
        orderField: {type: "LabelOrderField", defaultValue: NAME}
        orderDirection: {type: "OrderDirection", defaultValue: DESC}
        skip: {type: "Int!"}
        query: {type: "String"}
      ) {
        id
        nameWithOwner
        labels(
          query: $query
          first: $first
          after: $cursor
          orderBy: {field: $orderField, direction: $orderDirection}
          skip: $skip
        ) @connection(key: "LabelList_labels") {
          edges {
            node {
              id
              ...LabelRow
            }
          }
          totalCount
        }
        isWritable
        viewerCanPush
      }
    `,
    repositoryRef,
  )

  if (!data.labels) {
    throw new Error('labels data is null or undefined')
  }

  return <LabelListInternal data={data} loadNext={loadNext} hasNext={hasNext} onCreateLabel={onCreateLabel} />
}

function LabelListInternal({
  data,
  hasNext: _hasNext,
  loadNext: _loadNext,
  onCreateLabel,
}: {
  data: LabelList$data
  hasNext: boolean
  loadNext: LoadMoreFn<OperationType>
  onCreateLabel?: () => void
}) {
  const nodes = useMemo(() => {
    return data.labels?.edges?.map(edge => (edge?.node ? edge.node : null)).filter(node => !!node) || []
  }, [data])
  const [searchParams] = useSearchParams()

  const dataCount = data.labels?.totalCount || 0
  const metadataTitle = dataCount === 1 ? `1 label` : `${dataCount} labels`
  const isActionsAvailable = data.isWritable && data.viewerCanPush

  const actions = useMemo(() => {
    if (nodes.length === 0 || searchParams.get('q')) return []
    else {
      return [
        {
          key: 'label-sort-menu',
          render: () => <LabelSortMenu />,
        },
      ]
    }
  }, [nodes.length, searchParams])

  const listItemsHeader = <ListViewMetadata title={metadataTitle} actions={actions} actionsLabel="Label actions" />

  const [labelIssueAndPrCountRef, loadLabelIssueAndPrCount] = useQueryLoader<IssuesAndPullRequestsCountSecondaryQuery>(
    IssuesAndPullRequestsCountSecondaryQueryQ,
  )

  useEffect(() => {
    if (!IS_SERVER) {
      const labelIds = nodes.map(node => node.id)
      loadLabelIssueAndPrCount({nodes: labelIds})
    }
  }, [nodes, loadLabelIssueAndPrCount])

  return (
    <div className={styles.labelListWrapper} data-hpc>
      <ListView
        {...testIdProps('repository-label-list-view')}
        title="Labels"
        metadata={listItemsHeader}
        titleHeaderTag="h2"
        // role="status" doesn't add much for the static "no labels in repository" case,
        // but it's useful for the "no matches" case since that message is rendered dynamically after filtering.
        as={nodes.length > 0 ? 'ul' : 'div'}
        role={nodes.length > 0 ? 'list' : 'status'}
      >
        {nodes.length > 0 &&
          nodes.map(node => (
            <LabelRow
              key={node.id}
              label={node}
              isActionsAvailable={isActionsAvailable}
              viewerCanPush={data.viewerCanPush}
              secondaryQueryRef={labelIssueAndPrCountRef}
              repositoryId={data.id}
              repositoryNameWithOwner={data.nameWithOwner}
            />
          ))}
        {nodes.length === 0 && (
          <EmptyState
            noLabelsCreated={dataCount === 0}
            viewerCanPush={data.viewerCanPush}
            onCreateLabel={onCreateLabel}
          />
        )}
      </ListView>
      {nodes.length > 0 && <LabelListPagination dataCount={dataCount} />}
    </div>
  )
}

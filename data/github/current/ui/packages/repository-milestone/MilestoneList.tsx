import {ListView} from '@github-ui/list-view'
import {testIdProps} from '@github-ui/test-id-props'
import {graphql, usePaginationFragment, type LoadMoreFn} from 'react-relay'
import styles from './RepositoryMilestone.module.css'
import {useMemo} from 'react'
import type {MilestoneList$data, MilestoneList$key} from './__generated__/MilestoneList.graphql'
import type {OperationType} from 'relay-runtime'
import {MilestoneRow} from './MilestoneRow'
import {OpenClosedMilestones} from './OpenClosedMilestones'
import {ListViewMetadata} from '@github-ui/list-view/ListViewMetadata'
import {MilestoneSortMenu} from './MilestoneSortMenu'
import {VALUES} from './constants/values'
import {Button} from '@primer/react'
import {MilestoneEmptyState} from './MilestoneEmptyState'
import {ssrSafeLocation} from '@github-ui/ssr-utils'

type MilestoneListProps = {
  repositoryRef: MilestoneList$key
}

type MilestoneListInternalProps = {
  data: MilestoneList$data
  hasNext: boolean
  isLoadingNext: boolean
  loadNext: LoadMoreFn<OperationType>
}

export function MilestoneList({repositoryRef}: MilestoneListProps) {
  const {data, loadNext, hasNext, isLoadingNext} = usePaginationFragment(
    graphql`
      fragment MilestoneList on Repository
      @refetchable(queryName: "MilestoneListQuery")
      @argumentDefinitions(
        cursor: {type: "String", defaultValue: null}
        first: {type: "Int!"}
        state: {type: "MilestoneState!"}
        orderField: {type: "MilestoneOrderField", defaultValue: CREATED_AT}
        orderDirection: {type: "OrderDirection", defaultValue: DESC}
      ) {
        nameWithOwner
        milestones(
          first: $first
          after: $cursor
          states: [$state]
          orderBy: {field: $orderField, direction: $orderDirection}
        ) @connection(key: "MilestoneList_milestones") {
          edges {
            node {
              id
              ...MilestoneRow
            }
          }
        }
        open: milestones(first: 0, states: OPEN) {
          totalCount
        }
        closed: milestones(first: 0, states: CLOSED) {
          totalCount
        }
        ...OpenClosedMilestones
      }
    `,
    repositoryRef,
  )

  if (!data.milestones) {
    throw new Error('Milestones data is null or undefined')
  }

  return <MilestoneListInternal data={data} loadNext={loadNext} hasNext={hasNext} isLoadingNext={isLoadingNext} />
}

function MilestoneListInternal({data, hasNext, isLoadingNext, loadNext}: MilestoneListInternalProps) {
  const nodes = useMemo(() => {
    return data.milestones?.edges?.map(edge => (edge?.node ? edge.node : null)).filter(node => !!node) || []
  }, [data])
  const actions = useMemo(() => {
    return [
      {
        key: 'milestone-sort-menu',
        render: () => <MilestoneSortMenu />,
      },
    ]
  }, [])

  const rootUrl = `${ssrSafeLocation.origin}/${data.nameWithOwner}`
  const newMilestoneUrl = `${rootUrl}/milestones/new`

  const listItemsHeader = (
    <ListViewMetadata
      actions={actions}
      actionsLabel="Actions"
      sectionFilters={<OpenClosedMilestones repository={data} />}
    />
  )

  const loadMoreButton = useMemo(() => {
    return hasNext ? (
      <div className={styles.loadMoreButtonWrapper}>
        <Button
          variant="invisible"
          onClick={() => loadNext(VALUES.milestonePageSize)}
          className={styles.loadMoreButton}
          data-testid="load-more-milestones-button"
          loading={isLoadingNext}
        >
          Load more
        </Button>
      </div>
    ) : null
  }, [hasNext, isLoadingNext, loadNext])

  const renderMilestoneList = () => {
    if (nodes.length > 0) {
      return nodes.map(node => (
        <MilestoneRow key={node.id} milestone={node} repositoryNameWithOwner={data.nameWithOwner} />
      ))
    }

    const openCount = data.open?.totalCount ?? 0
    const closedCount = data.closed?.totalCount ?? 0
    const noCreatedMilestones = openCount === 0 && closedCount === 0

    return <MilestoneEmptyState noCreatedMilestones={noCreatedMilestones} newMilestoneUrl={newMilestoneUrl} />
  }

  return (
    <>
      <div className={styles.milestoneListWrapper} data-hpc>
        <ListView
          {...testIdProps('repository-milestone-list-view')}
          title=""
          metadata={listItemsHeader}
          titleHeaderTag="h2"
          singularUnits={'milestone'}
          pluralUnits={'milestones'}
          as={nodes.length > 0 ? 'ul' : 'div'}
          role={nodes.length > 0 ? 'list' : 'status'}
        >
          {renderMilestoneList()}
        </ListView>
      </div>
      {loadMoreButton}
    </>
  )
}

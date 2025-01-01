import {ListView} from '@github-ui/list-view'
import {testIdProps} from '@github-ui/test-id-props'
import {graphql, useFragment, usePaginationFragment, useRelayEnvironment, type LoadMoreFn} from 'react-relay'
import {EmptyState} from './components/EmptyState'
import styles from './RepositoryMilestone.module.css'
import {ListItemsHeader} from './components/ListItemsHeader'
import {OpenClosedMilestoneIssues} from './OpenClosedMilestoneIssues'
import type {ItemNodeType} from './types'
import {useState, useMemo, useCallback, useEffect} from 'react'
import type {MilestoneIssuesList$data, MilestoneIssuesList$key} from './__generated__/MilestoneIssuesList.graphql'
import {useLocalStorage} from '@github-ui/use-safe-storage/local-storage'
import {useShiftKey} from './utils/use-shift-key'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {prefetchIssue} from '@github-ui/issue-viewer/IssueViewerLoader'
import {IssueRow} from '@github-ui/list-view-items-issues-prs/IssueRow'
import {startSoftNav} from '@github-ui/soft-nav/state'
import {type To, type NavigateOptions, useSearchParams} from 'react-router-dom'
import {useNavigate} from '@github-ui/use-navigate'
import {VALUES} from './constants/values'
import {Button} from '@primer/react'
import type {OperationType} from 'relay-runtime'
import {VIEW_IDS} from '@github-ui/issue-url-helper/constants/view-constants'
import {searchUrl, replaceInQuery} from '@github-ui/issue-url-helper'
import type {QUERY_FIELDS} from '@github-ui/list-view-items-issues-prs/Queries'
import {DragAndDrop, type OnDropArgs} from '@github-ui/drag-and-drop'
import {commitReprioritizeMilestoneIssueMutation} from './mutations/reprioritize-milestone-issue'
import type {MilestoneIssuesListInternal$key} from './__generated__/MilestoneIssuesListInternal.graphql'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {MilestoneIssuesListPage} from './MilestoneIssuesListPage'
import {PullRequestRow} from '@github-ui/list-view-items-issues-prs/PullRequestRow'
import {noop} from '@github-ui/noop'

type MilestoneIssuesListProps = {
  repositoryRef: MilestoneIssuesList$key
  singleKeyShortcutsEnabled?: boolean
}

export function MilestoneIssuesList({repositoryRef, singleKeyShortcutsEnabled}: MilestoneIssuesListProps) {
  const {data, loadNext, hasNext} = usePaginationFragment(
    graphql`
      fragment MilestoneIssuesList on Repository
      @refetchable(queryName: "MilestoneIssuesListQuery")
      @argumentDefinitions(
        cursor: {type: "String", defaultValue: null}
        first: {type: "Int!"}
        query: {type: "String!"}
        number: {type: "Int!"}
      ) {
        search(query: $query, type: ISSUE_ADVANCED, first: $first, after: $cursor, aggregations: true)
          @connection(key: "MilestoneIssuesList_search") {
          issueCount
          edges {
            node {
              ... on Issue {
                id
                __typename
                number
                state
                ...IssueRow
                  @dangerously_unaliased_fixme
                  @arguments(labelPageSize: 10, fetchRepository: false, includeMilestone: false)
              }
              ... on PullRequest {
                id
                __typename
                number
                closed
                ...PullRequestRow_pullRequest
                  @dangerously_unaliased_fixme
                  @arguments(labelPageSize: 10, includeGitData: false, includeMilestone: false)
              }
            }
          }
        }
        milestone(number: $number) {
          ...MilestoneIssuesListInternal
        }
        owner {
          login
        }
        name
        id
        isArchived
        viewerCanPush
        isDisabled
        isLocked
        isInOrganization
      }
    `,
    repositoryRef,
  )

  if (!data.milestone) {
    return null
  }

  return (
    <MilestoneIssuesListInternal
      data={data}
      milestone={data.milestone}
      loadNext={loadNext}
      hasNext={hasNext}
      singleKeyShortcutsEnabled={singleKeyShortcutsEnabled}
      viewerCanPush={data.viewerCanPush}
    />
  )
}

export function MilestoneIssuesListInternal({
  data,
  milestone,
  loadNext,
  hasNext,
  singleKeyShortcutsEnabled,
  viewerCanPush,
}: {
  data: MilestoneIssuesList$data
  milestone: MilestoneIssuesListInternal$key
  hasNext: boolean
  loadNext: LoadMoreFn<OperationType>
  viewerCanPush: boolean
  singleKeyShortcutsEnabled?: boolean
}) {
  const milestoneData = useFragment(
    graphql`
      fragment MilestoneIssuesListInternal on Milestone {
        id
        number
        updatedAt
        ...OpenClosedMilestoneIssues
      }
    `,
    milestone,
  )

  const scoped_repository = useMemo(
    () => ({
      id: data.id,
      name: data.name,
      owner: data.owner.login,
      is_archived: data.isArchived,
      viewerCanPush: data.viewerCanPush,
      isDisabled: data.isDisabled,
      isLocked: data.isLocked,
    }),
    [data],
  )

  const [checkedItems, setCheckedItems] = useState(() => new Map<string, ItemNodeType>())

  const [lastSelectedItem, setLastSelectedItem] = useState<{id: string; node: ItemNodeType}>()
  const {shiftKeyPressedRef} = useShiftKey()

  const nodes = useMemo(() => {
    return (
      data.search?.edges
        ?.map(edge =>
          edge?.node && (edge.node.__typename === 'PullRequest' || edge.node.__typename === 'Issue') ? edge.node : null,
        )
        .filter(node => !!node) || []
    )
  }, [data])

  const environment = useRelayEnvironment()
  const navigate = useNavigate()
  const handleNavigate = useCallback(
    async (issueNumber: number, to: To, navOptions?: NavigateOptions) => {
      startSoftNav('react')
      await prefetchIssue(environment, data.owner.login, data.name, issueNumber)
      return navigate(to, navOptions)
    },
    [data.name, data.owner.login, environment, navigate],
  )

  const [bulkJobId, setBulkJobId] = useLocalStorage<string | null>(VALUES.localStorageKeyBulkUpdateIssues, null)

  const [listHasPRs, setListHasPRs] = useState(false)

  const isBulkSupported =
    scoped_repository &&
    scoped_repository.viewerCanPush &&
    !(scoped_repository.isDisabled || scoped_repository.isLocked || scoped_repository.is_archived) &&
    nodes.length < 100

  const useBulkActions = useMemo(() => {
    return isBulkSupported && !listHasPRs
  }, [listHasPRs, isBulkSupported])

  const updateListHasPRs = (checkedMap: Map<string, ItemNodeType>) => {
    const hasAnyPR = Array.from(checkedMap.values()).some(item => item.__typename === 'PullRequest')
    setListHasPRs(hasAnyPR)
  }

  const applyShiftSelection = useCallback(
    (newCheckedItems: Map<string, ItemNodeType>, fromId: string, toId: string, selected: boolean) => {
      const fromIndex = nodes.findIndex(d => d.id === fromId)
      const toIndex = nodes.findIndex(d => d.id === toId)
      for (let i = Math.min(fromIndex, toIndex); i <= Math.max(fromIndex, toIndex); i++) {
        const d = nodes[i]
        if (d) {
          if (selected) {
            newCheckedItems.set(d.id, d)
          } else {
            newCheckedItems.delete(d.id)
          }
        }
        updateListHasPRs(newCheckedItems)
      }
    },
    [nodes],
  )

  const itemSelected = useCallback(
    (id: string, node: ItemNodeType, selected: boolean) => {
      const newCheckedItems = new Map<string, ItemNodeType>(checkedItems)

      if (shiftKeyPressedRef.current && lastSelectedItem) {
        applyShiftSelection(newCheckedItems, lastSelectedItem.id, id, selected)
      } else {
        if (selected) {
          newCheckedItems.set(id, node)
        } else {
          newCheckedItems.delete(id)
        }
        updateListHasPRs(newCheckedItems)
      }

      setCheckedItems(newCheckedItems)
      setLastSelectedItem({id, node})
    },
    [applyShiftSelection, checkedItems, lastSelectedItem, shiftKeyPressedRef],
  )

  const getMetadataHref = useCallback((queryField: keyof typeof QUERY_FIELDS, metadataName: string) => {
    const href = searchUrl({
      viewId: VIEW_IDS.repository,
      query: replaceInQuery('is:issue state:open', queryField, metadataName),
    })
    return href
  }, [])

  const [orderedNodes, setOrderedNodes] = useState(nodes)

  const rootUrl = `${ssrSafeLocation.origin}/${data.owner.login}/${data.name}`
  const issuesWithNoMilestoneUrl = `${rootUrl}/issues/?q=is%3Aissue%20state%3Aopen%20no%3Amilestone`
  const currentMilestonePathname = `/${data.owner.login}/${data.name}/milestone/${milestoneData.number}`

  const pathName = ssrSafeLocation.pathname
  const [searchParams] = useSearchParams()
  const closedQuery = searchParams.get('closed')
  const isClosedSelectedTab = currentMilestonePathname === pathName && closedQuery === '1'

  function getNodeState(node: ItemNodeType) {
    if (node.__typename === 'Issue') {
      return node.state
    }
    if (node.__typename === 'PullRequest') {
      return node.closed ? 'CLOSED' : 'OPEN'
    }
    return null // Skip unsupported types
  }

  useEffect(() => {
    setOrderedNodes(prevOrderedNodes => {
      const selectedTab = isClosedSelectedTab ? 'CLOSED' : 'OPEN'
      // we need to keep track of the current tab nodes to make sure that new nodes are added at the bottom of the ordered list to not break the ordering
      const currentTabNodes = prevOrderedNodes.filter(node => {
        return getNodeState(node) === selectedTab
      })

      // Build a Set of existing keys (to avoid duplicates)
      const existingKeys = new Set(currentTabNodes.map(node => `${node.__typename}:${node.id}`))

      // Filter incoming nodes to match current tab and exclude duplicates
      const newNodes = nodes.filter(node => {
        return getNodeState(node) === selectedTab && !existingKeys.has(`${node.__typename}:${node.id}`)
      })

      // Merge the new nodes at the bottom of the current tab nodes.
      // If we are switching between the tabs, currentTabNodes will be an emoty array and the newNodes are the new tab's nodes.
      return [...currentTabNodes, ...newNodes]
    })
  }, [nodes, isClosedSelectedTab])
  const {addToast} = useToastContext()
  const handleDrop = useCallback(
    ({dragMetadata, dropMetadata, isBefore}: OnDropArgs<string>) => {
      if (dragMetadata.id === dropMetadata?.id) {
        return
      }
      const dragItem = orderedNodes.find(item => item.id === dragMetadata.id)
      const dropItemIndex = orderedNodes.findIndex(item => item.id === dropMetadata?.id)
      const dropItem = orderedNodes[dropItemIndex]

      if (dragItem && dropItem) {
        let prevId = null
        if (isBefore) {
          prevId = dropItemIndex > 0 ? orderedNodes[dropItemIndex - 1]?.id : null
        } else {
          prevId = dropItem.id
        }

        const newNodes = orderedNodes.reduce(
          (newItems, item) => {
            if (dragItem.id === item.id) {
              return newItems
            }
            if (item.id !== dropMetadata?.id) {
              newItems.push(item)
            } else if (isBefore) {
              newItems.push(dragItem, item)
            } else {
              newItems.push(item, dragItem)
            }
            return newItems
          },
          [] as typeof orderedNodes,
        )
        setOrderedNodes(newNodes)

        commitReprioritizeMilestoneIssueMutation({
          environment,
          input: {
            id: dragItem.id,
            milestoneId: milestoneData.id,
            timestamp: milestoneData.updatedAt,
            prevId,
          },
          onError: error => {
            if (error) {
              if (Array.isArray(error.cause) && error.cause[0] && error.cause[0].type === 'UNPROCESSABLE') {
                // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
                addToast({
                  type: 'info',
                  message: error.cause[0].message,
                  role: 'alert',
                })
              } else {
                // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
                addToast({
                  type: 'error',
                  message: 'Error while updating milestone issue ordering',
                  role: 'alert',
                })
              }
              setOrderedNodes(orderedNodes)
            }
          },
        })
      }
    },
    [addToast, environment, milestoneData.id, milestoneData.updatedAt, orderedNodes],
  )
  const issueCount = data.search?.issueCount || 0
  const withDragAndDrop = viewerCanPush && issueCount < VALUES.maxPrioritizableItemCount && !isClosedSelectedTab

  const paginatedNodes = useMemo(() => {
    const pageSize = VALUES.issuesPageSize
    const pages = []
    for (let i = 0; i < orderedNodes.length; i += pageSize) {
      pages.push(orderedNodes.slice(i, i + pageSize))
    }
    return pages
  }, [orderedNodes])

  const pages = paginatedNodes.map(pageNodes => {
    return (
      <MilestoneIssuesListPage
        key={pageNodes[0] ? pageNodes[0].id : 'my_key'}
        orderedNodes={pageNodes}
        checkedItems={checkedItems}
        itemSelected={itemSelected}
        getMetadataHref={getMetadataHref}
        withDragAndDrop={withDragAndDrop}
        scopedRepository={scoped_repository}
        handleNavigate={handleNavigate}
      />
    )
  })

  const listItemsHeader = (
    <ListItemsHeader
      checkedItems={checkedItems}
      scopedRepository={scoped_repository}
      isInOrganization={data.isInOrganization}
      sectionFilters={<OpenClosedMilestoneIssues milestoneRef={milestoneData} />}
      issueCount={issueCount}
      issueNodes={nodes.filter(Boolean).reduce((arr, node) => {
        arr.push(node)
        return arr
      }, new Array<ItemNodeType>())}
      setCheckedItems={setCheckedItems}
      updateListHasPRs={updateListHasPRs}
      useBulkActions={useBulkActions}
      singleKeyShortcutsEnabled={singleKeyShortcutsEnabled}
      bulkJobId={bulkJobId}
      setBulkJobId={setBulkJobId}
    />
  )

  const loadMorePage = useCallback(() => {
    loadNext(VALUES.issuesPageSize)
  }, [loadNext])

  const loadMoreButton = useMemo(() => {
    if (issueCount > VALUES.issuesPageSize) {
      return hasNext ? (
        <div className={styles.loadMoreButtonWrapper}>
          <Button
            variant="invisible"
            onClick={loadMorePage}
            className={styles.loadMoreButton}
            data-testid="load-more-button"
          >
            <span>Load more</span>
          </Button>
        </div>
      ) : null
    }
    return null
  }, [issueCount, hasNext, loadMorePage])

  return (
    <>
      <div className={styles.milestoneListWrapper} data-hpc>
        <ListView
          {...testIdProps('repository-milestone-list-view')}
          title=""
          as="div"
          role="none"
          totalCount={issueCount}
          selectedCount={checkedItems.size}
          titleHeaderTag="h2"
          isSelectable
          hasDragHandle={withDragAndDrop}
          metadata={listItemsHeader}
          singularUnits={'issue'}
          pluralUnits={'issues'}
        >
          {orderedNodes.length > 0 &&
            (withDragAndDrop ? (
              <DragAndDrop
                items={orderedNodes.map(item => ({id: item.id, title: ``}))}
                onDrop={handleDrop}
                className={styles.dndList}
                direction="vertical"
                role="list"
                aria-label="Issues list."
                renderOverlay={(_, index) => {
                  const node = orderedNodes[index]
                  if (!node) {
                    return null
                  }
                  let dragItem = null
                  if (node.__typename === 'Issue') {
                    dragItem = (
                      <IssueRow
                        metadataRef={null}
                        issueKey={node}
                        getMetadataHref={() => ''}
                        onSelectRow={noop}
                        isActive={false}
                        sortingItemSelected={''}
                        onNavigate={noop}
                      />
                    )
                  }
                  if (node.__typename === 'PullRequest') {
                    return (
                      <PullRequestRow
                        metadataRef={null}
                        pullRequestKey={node}
                        includeGitDataFromMainQuery={false}
                        getMetadataHref={() => ''}
                        onSelectRow={noop}
                        isActive={false}
                        sortingItemSelected={''}
                        onNavigate={noop}
                      />
                    )
                  }

                  return (
                    <DragAndDrop.Item
                      hideSortableItemTrigger
                      as="li"
                      index={index}
                      id={'dragItem'}
                      key={'dragItem'}
                      title={''}
                      isDragOverlay
                      containerStyle={{display: 'flex', width: '100%'}}
                      style={{listStyle: 'none'}}
                    >
                      {dragItem}
                    </DragAndDrop.Item>
                  )
                }}
              >
                {pages}
              </DragAndDrop>
            ) : (
              <>{pages}</>
            ))}
          {pages.length === 0 && (
            <EmptyState selected={isClosedSelectedTab ? 'closed' : 'open'} descriptionUrl={issuesWithNoMilestoneUrl} />
          )}
        </ListView>
      </div>
      {loadMoreButton}
    </>
  )
}

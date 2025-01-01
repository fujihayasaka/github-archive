import {ListView} from '@github-ui/list-view'
import {IssueRow, IssuesIndexSecondaryGraphqlQuery} from '@github-ui/list-view-items-issues-prs/IssueRow'
import {NoResults} from '@github-ui/list-view-items-issues-prs/NoResults'
import {PullRequestRow} from '@github-ui/list-view-items-issues-prs/PullRequestRow'
import type {QUERY_FIELDS} from '@github-ui/list-view-items-issues-prs/Queries'
import {isPrsOnly, parseQuery} from '@github-ui/query-builder/utils/query'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {EMOJI_MAP} from '@github-ui/reaction-viewer/ReactionGroupsUtils'
import {IS_SERVER, ssrSafeLocation} from '@github-ui/ssr-utils'
import {testIdProps} from '@github-ui/test-id-props'
import type {AnalyticsEvent} from '@github-ui/use-analytics'
import {Box, Pagination} from '@primer/react'
import {useCallback, useEffect, useMemo, useRef, useState, type MouseEvent, type MutableRefObject} from 'react'
import {graphql, usePaginationFragment} from 'react-relay'
import {useQueryLoader} from 'react-relay/hooks'
import type {NavigateOptions, To} from 'react-router-dom'

import {announce} from '@github-ui/aria-live'
import type {IssueRowSecondaryQuery} from '@github-ui/list-view-items-issues-prs/IssuesIndexSecondaryQuery'
import {checkIfQuerySupportsPr} from '@github-ui/list-view-items-issues-prs/Query'
import {useNavigate} from '@github-ui/use-navigate'
import {LABELS} from '../../constants/labels'
import {TEST_IDS} from '../../constants/test-ids'
import {VALUES} from '../../constants/values'
import {useQueryContext} from '../../contexts/QueryContext'
import {useAppNavigate} from '../../hooks/use-app-navigate'
import {useHyperlistAnalytics} from '../../hooks/use-hyperlist-analytics'
import type {AppPayload} from '../../types/app-payload'
import {getPageNumberFromUrlQuery, replacePageNumberInUrl} from '../../utils/urls'
import type {
  ListItemsPaginated_results$data,
  ListItemsPaginated_results$key,
} from './__generated__/ListItemsPaginated_results.graphql'
import type {SearchPaginatedQuery} from './__generated__/SearchPaginatedQuery.graphql'
import {ListItemsHeader} from './header/ListItemsHeader'
import {useShiftKey} from './hooks/use-shift-key'
import {MoreResultsAvailableBanner} from './MoreResultsAvailableBanner'
import {GlobalCommands, ScopedCommands} from '@github-ui/ui-commands'
import {noop} from '@github-ui/noop'
import styles from './ListItems.module.css'
import {useUser} from '@github-ui/use-user'
import {
  getSelectedSortOptionKeyFromQuery,
  handleEmojiMapValue,
} from '@github-ui/list-view-items-issues-prs/SortingDropdown'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import {useIsPlatform} from '@github-ui/use-is-platform'
import type {ReportableError} from '@github-ui/relay-preloaded-query-boundary'
import type {ItemIdentifier} from '@github-ui/issue-viewer/Types'
import {useSessionStorage} from '@github-ui/use-safe-storage/session-storage'

type ListProps = {
  search: ListItemsPaginated_results$key
  queryFromCustomView?: string | null
  listRef: MutableRefObject<HTMLUListElement | undefined>
  isBulkSupported: boolean
  isInOrganization?: boolean
  includeGitDataFromMainQuery?: boolean
  onSidePanelNavigate?: (issue: ItemIdentifier) => void
}

type PaginationQueryProps = {
  key: ListItemsPaginated_results$key
}

const ListItemsFragment = graphql`
  fragment ListItemsPaginated_results on Searchable
  @argumentDefinitions(
    cursor: {type: "String", defaultValue: null}
    query: {type: "String!"}
    first: {type: "Int"}
    labelPageSize: {type: "Int!"}
    skip: {type: "Int", defaultValue: null}
    fetchRepository: {type: "Boolean!"}
    includeGitData: {type: "Boolean", defaultValue: false}
  )
  @refetchable(queryName: "SearchPaginatedQuery") {
    search(first: $first, after: $cursor, query: $query, type: ISSUE_ADVANCED, skip: $skip)
      @catch(to: RESULT)
      @stream_connection(key: "Query_search", initial_count: 12) {
      edges @required(action: THROW) {
        node {
          ... on Issue {
            id
            __typename
            number
            ...IssueRow
              @dangerously_unaliased_fixme
              @arguments(labelPageSize: $labelPageSize, fetchRepository: $fetchRepository)
          }
          ... on PullRequest {
            id
            __typename
            number
            ...PullRequestRow_pullRequest
              @dangerously_unaliased_fixme
              @arguments(labelPageSize: $labelPageSize, includeGitData: $includeGitData)
          }
        }
      }
      pageInfo {
        startCursor
        endCursor
        hasPreviousPage
        hasNextPage
      }
      issueCount
    }
  }
`

function SearchFunction({key}: PaginationQueryProps) {
  const {data, refetch} = usePaginationFragment<SearchPaginatedQuery, ListItemsPaginated_results$key>(
    ListItemsFragment,
    key,
  )

  return {data, refetch}
}

/**
 * See ListView stories for a representation of this component.
 * ui/packages/list-view/src/stories/RecentActivity/RecentActivity.stories.tsx
 * https://ui.githubapp.com/storybook/?path=/story/recipes-list-view-dotcom-pages--recent-activity
 * https://ui.githubapp.com/storybook/?path=/story/recipes-list-view-dotcom-pages--repository-issues
 */

/* A list of issues or pull requests that can be rendered in the sidebar or in the main content area.
 * @param {ItemIdentifier} itemIdentifier - Identifier for the current item displayed in the viewer (when the list is
      present in the sidebar). Undefined when the viewer is closed
 * @param {string} queryFromCustomView - The query corresponding to the custom view (if any)
 */
export function ListItems({
  search,
  queryFromCustomView,
  listRef,
  isBulkSupported,
  includeGitDataFromMainQuery = false,
  isInOrganization,
  onSidePanelNavigate,
}: ListProps) {
  const path = `${ssrSafeLocation.pathname}${ssrSafeLocation.search}`

  const {scoped_repository} = useAppPayload<AppPayload>()
  const {currentUser} = useUser()
  const {activeSearchQuery, currentPage, setCurrentPage} = useQueryContext()
  const [fromPagination, setFromPagination] = useState(false)
  const navigate = useNavigate()
  const isMac = useIsPlatform(['mac'])

  const [lastSelectedItem, setLastSelectedItem] = useState<{id: string; node: ItemNodeType}>()
  const {shiftKeyPressedRef} = useShiftKey()
  const {issues_react_bypass_es_limits} = useFeatureFlags()
  const bypassEsLimits = issues_react_bypass_es_limits || false

  const [issueIndexLazyDataRef, loadIssueIndexLazyData] = useQueryLoader<IssueRowSecondaryQuery>(
    IssuesIndexSecondaryGraphqlQuery,
  )

  const {data: pageData, refetch} = SearchFunction({key: search})
  const searchDataMissing = pageData.search === null || pageData.search === undefined

  const errors = pageData.search?.ok ? null : pageData.search?.errors

  if (!pageData.search.ok) {
    const isServiceUnavailable = errors?.some(
      e => e && typeof e === 'object' && 'type' in e && e.type === 'SERVICE_UNAVAILABLE',
    )

    const errorMessage = `ListItemsPaginated: pageData.search.value.edges is errored. Errors: ${JSON.stringify(errors)}`
    const error: ReportableError = new Error(errorMessage)
    error.shouldSkipReport = isServiceUnavailable ?? false
    throw error
  }

  const {ok, value: {edges, issueCount} = {}} = pageData.search
  const hasValidEdges = edges !== null && edges !== undefined
  const searchResultsReady = !searchDataMissing && ok && hasValidEdges

  // just to make sure we don't refetch the data more than once
  const [refetched, setRefetched] = useState(false)

  // Workaround until we find a way to fix an issue where the data is null when we have the data in the browser cache
  // but it's marked as stale by Relay. See https://github.com/github/issues/issues/13005
  const shouldRefetch = useMemo(() => {
    const hasValidParentNode = pageData.id && pageData.id !== 'RootQueryObject'
    return !refetched && searchDataMissing && hasValidParentNode
  }, [refetched, searchDataMissing, pageData])

  useEffect(() => {
    announce(LABELS.numberOfResults(issueCount || 0), {assertive: true})
  }, [issueCount])

  useEffect(() => {
    if (!shouldRefetch) return

    const disposable = refetch({}, {fetchPolicy: 'network-only', onComplete: () => setRefetched(true)})

    // cleanup
    return disposable.dispose
  }, [activeSearchQuery, refetch, searchDataMissing, shouldRefetch])

  const data = useMemo(
    () =>
      edges
        ? edges
            .map(edge =>
              edge?.node && (edge.node.__typename === 'PullRequest' || edge.node.__typename === 'Issue')
                ? edge.node
                : null,
            )
            .filter(node => node != null)
        : [],
    [edges],
  )

  const paginationLoadingRef = useRef<HTMLDivElement>(null)

  const onlyPrs = useMemo(() => {
    return isPrsOnly(activeSearchQuery)
  }, [activeSearchQuery])

  const maxItems = VALUES.maxIssuesListItems(bypassEsLimits, onlyPrs, !!currentUser)

  const totalPages = useMemo(() => {
    if (!issueCount) {
      return 0
    }

    const cappedIssueCount = Math.min(maxItems, issueCount)
    return Math.ceil(cappedIssueCount / VALUES.issuesPageSize())
  }, [issueCount, maxItems])

  const {getQueryFieldUrl, navigateToUrl} = useAppNavigate()

  const handlePageChange = useCallback(
    (e: MouseEvent, page_number: number) => {
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      const isMetaKey = isMac ? e.metaKey : e.ctrlKey
      if (isMetaKey || e.shiftKey) {
        return
      }
      e.preventDefault()

      const updatedUrl = replacePageNumberInUrl(path, page_number)
      setCurrentPage(page_number)
      navigateToUrl(updatedUrl)
    },
    [isMac, path, setCurrentPage, navigateToUrl],
  )

  const buildPageHref = useCallback(
    (page_number: number) => {
      return replacePageNumberInUrl(path, page_number)
    },
    [path],
  )

  const {initialSortingItem, initialReactionEmojiToDisplay} = useMemo(() => {
    const parsedSortQuery = parseQuery(queryFromCustomView || activeSearchQuery).get('sort')

    const selectedKey = getSelectedSortOptionKeyFromQuery(parsedSortQuery?.[0] || '')

    const reactionEmojiText = handleEmojiMapValue(selectedKey)
    const reactionEmoji = EMOJI_MAP[reactionEmojiText || '']

    return {
      initialSortingItem: selectedKey || 'created',
      initialReactionEmojiToDisplay: reactionEmoji ? {reaction: reactionEmojiText || '', reactionEmoji} : undefined,
    }
  }, [activeSearchQuery, queryFromCustomView])

  const [reactionEmojiToDisplay, setReactionEmojiToDisplay] = useState(initialReactionEmojiToDisplay)
  const [sortingItemSelected, setSortingItemSelected] = useState<string>(initialSortingItem)
  const [listHasPRs, setListHasPRs] = useState(false)

  const {sendHyperlistAnalyticsEvent} = useHyperlistAnalytics()

  const useBulkActions = useMemo(() => {
    return isBulkSupported && !checkIfQuerySupportsPr(activeSearchQuery)
  }, [activeSearchQuery, isBulkSupported])

  const [checkedItems, setCheckedItems] = useState(() => new Map<string, ItemNodeType>())

  const updateListHasPRs = (checkedMap: Map<string, ItemNodeType>) => {
    const hasAnyPR = Array.from(checkedMap.values()).some(item => item.__typename === 'PullRequest')
    setListHasPRs(hasAnyPR)
  }

  const applyShiftSelection = useCallback(
    (newCheckedItems: Map<string, ItemNodeType>, fromId: string, toId: string, selected: boolean) => {
      const fromIndex = data.findIndex(d => d.id === fromId)
      const toIndex = data.findIndex(d => d.id === toId)
      for (let i = Math.min(fromIndex, toIndex); i <= Math.max(fromIndex, toIndex); i++) {
        const d = data[i] as ItemNodeType
        if (selected) {
          newCheckedItems.set(d.id, d)
        } else {
          newCheckedItems.delete(d.id)
        }
        updateListHasPRs(newCheckedItems)
      }
    },
    [data],
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

  useEffect(() => {
    // If the underlying data changes, sync the data in `checkedItems` so child components that
    // read inline from those items have updated data.
    const anyMismatches = Array.from(checkedItems.values()).find(item => !data.find(node => node === item))
    if (anyMismatches) {
      setCheckedItems(
        data.reduce((map, item) => {
          if (item && checkedItems.has(item.id)) {
            map.set(item.id, item)
          }
          return map
        }, new Map<string, ItemNodeType>()),
      )
    }
  }, [checkedItems, data])

  useEffect(() => {
    const pageNumber = getPageNumberFromUrlQuery(ssrSafeLocation.search)
    setCurrentPage(pageNumber > 1 ? pageNumber : 1)
    setCheckedItems(new Map<string, ItemNodeType>())
  }, [setCurrentPage, path])

  const listItemsHeader = (
    <ListItemsHeader
      checkedItems={checkedItems}
      issueCount={issueCount || 0}
      issueNodes={data
        .filter(node => node != null)
        .reduce((arr, node) => {
          if (node) {
            arr.push(node)
          }
          return arr
        }, new Array<ItemNodeType>())}
      sortingItemSelected={sortingItemSelected}
      setCheckedItems={setCheckedItems}
      setReactionEmojiToDisplay={setReactionEmojiToDisplay}
      setSortingItemSelected={setSortingItemSelected}
      useBulkActions={useBulkActions}
      setCurrentPage={setCurrentPage}
      listHasPRs={listHasPRs}
      updateListHasPRs={updateListHasPRs}
      isInOrganization={isInOrganization}
    />
  )

  const getMetadataHref = (queryField: keyof typeof QUERY_FIELDS, metadataName: string) => {
    return getQueryFieldUrl(queryField, metadataName)
  }

  const onSelectRow = useCallback(
    (payload?: {[key: string]: unknown} | AnalyticsEvent | undefined) => {
      sendHyperlistAnalyticsEvent('search_results.select_row', 'SEARCH_RESULT_ROW', {...payload})
    },
    [sendHyperlistAnalyticsEvent],
  )

  const currentPageNodes = data

  const currentPageNodeTypes = new Set(currentPageNodes?.map(node => node?.__typename) || [])
  const handleNavigate = useCallback(
    (to: To, options = {}) => {
      return navigateToUrl(to, options, true)
    },
    [navigateToUrl],
  )
  const [deletedRecordId] = useSessionStorage<string>(
    `${scoped_repository?.owner}-${scoped_repository?.name}-deletedRecordId`,
    '',
  )
  const nodes = useMemo(
    () =>
      data
        .map(node => node?.id)
        .filter(id => id !== deletedRecordId)
        .filter(Boolean),
    [data, deletedRecordId],
  )

  const hasLazyData = issueIndexLazyDataRef !== null
  useEffect(() => {
    if (!IS_SERVER) {
      // The app currently fires loadIssueIndexLazyData twice on paginations.
      // The following prevents that.  Unfortunately, this introduced a bug where the secondary query wasn't being fired at all for other navigation types
      // For now we're commenting it out to fix the regression, but a followup item is needed to eliminate the duplicate queries during paging.
      // if (hasLazyData) {
      //   // This fixes an issue where the secondary query was being fired twice in certain navigations
      //   return
      // }
      loadIssueIndexLazyData({nodes, includeReactions: !!initialReactionEmojiToDisplay || false})
    }
  }, [initialReactionEmojiToDisplay, loadIssueIndexLazyData, nodes, hasLazyData])

  const items = currentPageNodes?.map(node => {
    const sharedRowData = {
      key: node?.id,
      isActive: false,
      isSelected: node && checkedItems.has(node.id) ? true : false,
      getMetadataHref,
      onSelect: (selected: boolean) => node && itemSelected(node.id, node, selected),
      onSelectRow,
      reactionEmojiToDisplay,
      sortingItemSelected,
      scopedRepository: scoped_repository,
    }
    if (node == null || node.id === deletedRecordId) {
      return null
    }

    return (
      <div key={node.id} className={styles.listItem}>
        {node.__typename === 'Issue' && (
          <IssueRow
            issueKey={node}
            metadataRef={issueIndexLazyDataRef}
            {...sharedRowData}
            data-testid={TEST_IDS.issueRowItem(node?.number || '-1')}
            key={sharedRowData.key}
            onNavigate={(to: To, options?: NavigateOptions) => handleNavigate(to, options)}
            onSidePanelNavigate={onSidePanelNavigate}
            getMetadataHref={getMetadataHref}
          />
        )}
        {node.__typename === 'PullRequest' && (
          <PullRequestRow
            pullRequestKey={node}
            metadataRef={issueIndexLazyDataRef}
            onNavigate={navigate}
            {...sharedRowData}
            data-testid={TEST_IDS.pullRequestRowItem(node?.number || '-1')}
            key={sharedRowData.key}
            getMetadataHref={getMetadataHref}
            includeGitDataFromMainQuery={includeGitDataFromMainQuery}
          />
        )}
      </div>
    )
  })

  useEffect(() => {
    if (fromPagination && currentPage) {
      announce(LABELS.announcePage(currentPage, totalPages, items.length))
      setFromPagination(false)
    }
  }, [currentPage, fromPagination, items.length, totalPages])

  const showMoreResultsAvailableBanner =
    currentPage !== undefined && totalPages === currentPage && issueCount !== undefined && issueCount > maxItems

  const focusTabbableIssue = () => {
    if (listRef.current) {
      // either the first issue in the list or the last tabbed item have a tabindex of 0, while the rest have -1
      // this is the primer implementation of navigating the list with tabs / keys
      const tabbableItem = listRef.current.querySelector('[tabindex="0"]')
      if (tabbableItem && tabbableItem instanceof HTMLElement) {
        tabbableItem.focus()
      }
    }
  }

  const list = (
    <>
      <GlobalCommands
        commands={{
          'issues-react:focus-next-issue': focusTabbableIssue,
          'issues-react:focus-previous-issue': focusTabbableIssue,
        }}
      />
      <Box
        data-testid="list-load-progress-bar"
        ref={paginationLoadingRef}
        className="turbo-progress-bar" // this is statically defined on the website level
        sx={{
          width: '0%',
        }}
      />
      {/* if we already have focus in the list, delegate keyboard navigation to ListView */}
      <ScopedCommands
        commands={{'issues-react:focus-next-issue': noop, 'issues-react:focus-previous-issue': noop}}
        className={styles.listScopedCommand}
      >
        <ListView
          {...testIdProps(TEST_IDS.list)}
          title={LABELS.searchResults}
          totalCount={issueCount || 0}
          selectedCount={checkedItems.size}
          titleHeaderTag="h2"
          isSelectable={useBulkActions}
          metadata={listItemsHeader}
          singularUnits={LABELS.singularUnits(currentPageNodeTypes)}
          pluralUnits={LABELS.pluralUnits(currentPageNodeTypes)}
          listRef={listRef}
        >
          {items}
          {items.length === 0 && searchResultsReady && <NoResults />}
          {showMoreResultsAvailableBanner && (
            <MoreResultsAvailableBanner itemsLabel={LABELS.pluralUnits(currentPageNodeTypes) ?? 'issues'} />
          )}
        </ListView>
      </ScopedCommands>
    </>
  )

  return (
    <div>
      <Box sx={{border: '1px solid', borderColor: 'border.default', borderRadius: 2}} data-hpc>
        {list}
      </Box>
      {currentPage && totalPages > 1 ? (
        <Pagination
          pageCount={totalPages}
          currentPage={currentPage}
          onPageChange={handlePageChange}
          hrefBuilder={buildPageHref}
          marginPageCount={2}
          surroundingPageCount={2}
        />
      ) : null}
    </div>
  )
}

type ArrayElement<ArrayType extends readonly unknown[]> = ArrayType extends ReadonlyArray<infer ElementType>
  ? ElementType
  : never

type NodeType = NonNullable<
  NonNullable<
    ArrayElement<NonNullable<Extract<ListItemsPaginated_results$data['search'], {ok: true}>['value']['edges']>>
  >['node']
>

type PullRequestNodeType = Extract<NodeType, {__typename: 'PullRequest'}>

export type IssueNodeType = Extract<NodeType, {__typename: 'Issue'}>
export type ItemNodeType = IssueNodeType | PullRequestNodeType

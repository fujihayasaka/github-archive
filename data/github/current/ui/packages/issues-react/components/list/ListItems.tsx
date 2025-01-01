import {ListView} from '@github-ui/list-view'
import {IssueRow, IssuesIndexSecondaryGraphqlQuery} from '@github-ui/list-view-items-issues-prs/IssueRow'
import {NoResults} from '@github-ui/list-view-items-issues-prs/NoResults'
import {PullRequestRow} from '@github-ui/list-view-items-issues-prs/PullRequestRow'
import type {QUERY_FIELDS} from '@github-ui/list-view-items-issues-prs/Queries'
import {findSortReactionInQuery, isPrsOnly, parseQuery} from '@github-ui/query-builder/utils/query'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {EMOJI_MAP} from '@github-ui/reaction-viewer/ReactionGroupsUtils'
import {IS_SERVER, ssrSafeLocation, ssrSafeWindow} from '@github-ui/ssr-utils'
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

type ListProps = {
  search: ListItemsPaginated_results$key
  queryFromCustomView?: string | null
  listRef: MutableRefObject<HTMLUListElement | undefined>
  isBulkSupported: boolean
  includeGitDataFromMainQuery?: boolean
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
      @stream_connection(key: "Query_search", initial_count: 12) {
      edges @required(action: THROW) {
        node {
          ... on Issue {
            id
            __typename
            number
            ...IssueRow @arguments(labelPageSize: $labelPageSize, fetchRepository: $fetchRepository)
          }
          ... on PullRequest {
            id
            __typename
            number
            ...PullRequestRow_pullRequest @arguments(labelPageSize: $labelPageSize, includeGitData: $includeGitData)
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
  const {issues_react_bypass_es_limits, issues_react_new_sort_dropdown: useNewSortDropdown} = useFeatureFlags()
  const bypassEsLimits = issues_react_bypass_es_limits || false

  const [issueIndexLazyDataRef, loadIssueIndexLazyData] = useQueryLoader<IssueRowSecondaryQuery>(
    IssuesIndexSecondaryGraphqlQuery,
  )

  const {data: pageData, refetch} = SearchFunction({key: search})
  const searchDataMissing = pageData.search === null || pageData.search === undefined
  const searchResultsReady = !searchDataMissing && pageData.search.edges !== null && pageData.search.edges !== undefined

  // just to make sure we don't refetch the data more than once
  const [refetched, setRefetched] = useState(false)

  // Workaround until we find a way to fix an issue where the data is null when we have the data in the browser cache
  // but it's marked as stale by Relay. See https://github.com/github/issues/issues/13005
  const shouldRefetch = useMemo(() => {
    const hasValidParentNode = pageData.id && pageData.id !== 'RootQueryObject'
    return !refetched && searchDataMissing && hasValidParentNode
  }, [refetched, searchDataMissing, pageData])

  useEffect(() => {
    if (!shouldRefetch) return

    const disposable = refetch({}, {fetchPolicy: 'network-only', onComplete: () => setRefetched(true)})

    // cleanup
    return disposable.dispose
  }, [activeSearchQuery, refetch, searchDataMissing, shouldRefetch])

  const data = useMemo(
    () =>
      pageData.search?.edges
        ? pageData.search.edges
            .map(edge =>
              edge?.node && (edge.node.__typename === 'PullRequest' || edge.node.__typename === 'Issue')
                ? edge.node
                : null,
            )
            .filter(node => node != null)
        : [],
    [pageData.search?.edges],
  )

  const paginationLoadingRef = useRef<HTMLDivElement>(null)

  const onlyPrs = useMemo(() => {
    return isPrsOnly(activeSearchQuery)
  }, [activeSearchQuery])

  const totalPages = useMemo(() => {
    if (!pageData.search?.issueCount) {
      return 0
    }

    const cappedIssueCount = Math.min(
      VALUES.maxIssuesListItems(bypassEsLimits, onlyPrs, !!currentUser),
      pageData.search.issueCount,
    )
    return Math.ceil(cappedIssueCount / VALUES.issuesPageSize())
  }, [bypassEsLimits, currentUser, onlyPrs, pageData.search?.issueCount])

  const handlePageChange = useCallback(
    (e: MouseEvent, page_number: number) => {
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      const isMetaKey = isMac ? e.metaKey : e.ctrlKey
      if (isMetaKey || e.shiftKey) {
        return
      }

      e.preventDefault()
      setCurrentPage(page_number)
      setLastSelectedItem(undefined)

      paginationLoadingRef.current?.style.setProperty('width', '95%')
      paginationLoadingRef.current?.style.setProperty('display', 'none')
      paginationLoadingRef.current?.style.setProperty('width', '0%')
      ssrSafeWindow?.scrollTo({top: 0, behavior: 'auto'})

      const updatedUrl = replacePageNumberInUrl(path, page_number)

      navigate(updatedUrl)

      setFromPagination(true)
    },
    [navigate, path, setCurrentPage, isMac],
  )

  // Duplicating the logic from SortingOptionsMenu to get a correct initial state (for SSR)
  const {initialSortingItem, initialReactionEmojiToDisplay} = useMemo(() => {
    const parsedSortQuery = parseQuery(queryFromCustomView || activeSearchQuery).get('sort')

    const sortText = `sort:${parsedSortQuery?.[0]}`

    if (useNewSortDropdown) {
      const selectedKey = getSelectedSortOptionKeyFromQuery(parsedSortQuery?.[0] || '')

      const reactionEmojiText = handleEmojiMapValue(selectedKey)
      const reactionEmoji = EMOJI_MAP[reactionEmojiText || '']

      return {
        initialSortingItem: selectedKey || 'created',
        initialReactionEmojiToDisplay: reactionEmoji ? {reaction: reactionEmojiText || '', reactionEmoji} : undefined,
      }
    } else {
      const selectedLabel = sortText && LABELS.sortingLabels[sortText]

      const sortReactionQuery = findSortReactionInQuery(queryFromCustomView || activeSearchQuery)

      const reactionEmojiText = selectedLabel?.replace(' ', '_').toUpperCase()
      const reactionEmoji = selectedLabel && reactionEmojiText && EMOJI_MAP[reactionEmojiText]!

      return {
        initialSortingItem: selectedLabel
          ? sortReactionQuery
            ? `${reactionEmoji} ${selectedLabel}`
            : selectedLabel
          : LABELS.Newest,
        initialReactionEmojiToDisplay: reactionEmoji ? {reaction: reactionEmojiText || '', reactionEmoji} : undefined,
      }
    }
  }, [activeSearchQuery, queryFromCustomView, useNewSortDropdown])

  const [reactionEmojiToDisplay, setReactionEmojiToDisplay] = useState(initialReactionEmojiToDisplay)
  const [sortingItemSelected, setSortingItemSelected] = useState<string>(initialSortingItem)

  const {sendHyperlistAnalyticsEvent} = useHyperlistAnalytics()
  const {getQueryFieldUrl, navigateToUrl} = useAppNavigate()

  const useBulkActions = useMemo(() => {
    return isBulkSupported && !checkIfQuerySupportsPr(activeSearchQuery)
  }, [activeSearchQuery, isBulkSupported])

  const [checkedItems, setCheckedItems] = useState(() => new Map<string, ItemNodeType>())

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
    // We only want to run this on initial load
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const listItemsHeader = (
    <ListItemsHeader
      checkedItems={checkedItems}
      issueCount={pageData.search?.issueCount || 0}
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

  const nodes = useMemo(() => data.map(node => node?.id).filter(Boolean), [data])

  useEffect(() => {
    if (!IS_SERVER) {
      loadIssueIndexLazyData({nodes, includeReactions: !!initialReactionEmojiToDisplay || false})
    }
  }, [initialReactionEmojiToDisplay, loadIssueIndexLazyData, nodes])

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
    if (node == null) {
      return null
    }

    if (node.__typename === 'Issue') {
      return (
        <IssueRow
          issueKey={node}
          metadataRef={issueIndexLazyDataRef}
          {...sharedRowData}
          data-testid={TEST_IDS.issueRowItem(node?.number || '-1')}
          key={sharedRowData.key}
          onNavigate={(to: To, options?: NavigateOptions) => handleNavigate(to, options)}
          getMetadataHref={getMetadataHref}
        />
      )
    }

    if (node.__typename === 'PullRequest') {
      return (
        <PullRequestRow
          pullRequestKey={node}
          metadataRef={issueIndexLazyDataRef}
          onNavigate={navigate}
          {...sharedRowData}
          data-testid={TEST_IDS.pullRequestRowItem(node?.number || '-1')}
          key={sharedRowData.key}
          showAvatar={activeSearchQuery.indexOf('is:pr') > -1}
          getMetadataHref={getMetadataHref}
          includeGitDataFromMainQuery={includeGitDataFromMainQuery}
        />
      )
    }
  })

  useEffect(() => {
    if (fromPagination && currentPage) {
      announce(LABELS.announcePage(currentPage, totalPages, items.length))
      setFromPagination(false)
    }
  }, [currentPage, fromPagination, items.length, totalPages])

  const showMoreResultsAvailableBanner =
    totalPages === currentPage &&
    pageData.search?.issueCount > VALUES.maxIssuesListItems(bypassEsLimits, onlyPrs, !!currentUser)

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
          totalCount={pageData.search?.issueCount || 0}
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
          marginPageCount={2}
          surroundingPageCount={2}
          hrefBuilder={page_number => replacePageNumberInUrl(path, page_number)}
        />
      ) : null}
    </div>
  )
}

type ArrayElement<ArrayType extends readonly unknown[]> = ArrayType extends ReadonlyArray<infer ElementType>
  ? ElementType
  : never

type NodeType = NonNullable<
  NonNullable<ArrayElement<NonNullable<ListItemsPaginated_results$data['search']['edges']>>>['node']
>

type PullRequestNodeType = Extract<NodeType, {__typename: 'PullRequest'}>

export type IssueNodeType = Extract<NodeType, {__typename: 'Issue'}>
export type ItemNodeType = IssueNodeType | PullRequestNodeType

import {SortingDropdown} from '@github-ui/list-view-items-issues-prs/SortingDropdown'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {Spinner} from '@primer/react'
import {useCallback, useMemo, useState} from 'react'
import {useListViewSelection} from '@github-ui/list-view/ListViewSelectionContext'
import {useListViewMultiPageSelection} from '@github-ui/list-view/ListViewMultiPageSelectionContext'
import {ListViewMetadata} from '@github-ui/list-view/ListViewMetadata'
import {LABELS} from '../../../constants/labels'
import {useQueryContext, useQueryEditContext} from '../../../contexts/QueryContext'
import type {AppPayload} from '../../../types/app-payload'
import {searchUrl} from '@github-ui/issue-url-helper'
import type {ListItemsHeaderProps} from './ListItemsHeader'
import {OpenClosedTabs} from './OpenClosedTabs'
import type {Action} from '@github-ui/action-bar'
import {ListLabelFilter} from './ListLabelFilter'
import type {ScopedRepository} from '@github-ui/list-view-items-issues-prs/Query'
import {ListProjectFilter} from './ListProjectFilter'
import {ListMilestoneFilter} from './ListMilestoneFilter'
import {ListAssigneeFilter} from './ListAssigneeFilter'
import {ListAuthorFilter} from './ListAuthorFilter'
import {ListIssueTypeFilter} from './ListIssueTypeFilter'
import {useAppNavigate} from '../../../hooks/use-app-navigate'

import styles from './ListItemsHeaderWithoutBulkActions.module.css'
import {IS_BROWSER} from '@github-ui/ssr-utils'

export type FilterBarPickerProps = {
  nested?: boolean
  repo: ScopedRepository
  applySectionFilter: (href: string, url: string) => void
}

export function ListItemsHeaderWithoutBulkActions({
  issueCount,
  issueNodes,
  setCheckedItems,
  setReactionEmojiToDisplay,
  setSortingItemSelected,
  setCurrentPage,
  updateListHasPRs,
  isInOrganization,
  ...rest
}: ListItemsHeaderProps) {
  const {scoped_repository} = useAppPayload<AppPayload>()
  const {dirtySearchQuery, setDirtySearchQuery} = useQueryEditContext()
  const {activeSearchQuery, isQueryLoading, currentViewId} = useQueryContext()
  const {navigateToUrl} = useAppNavigate()
  const results = useMemo(() => LABELS.numberOfResults(issueCount), [issueCount])

  const applySectionFilter = useCallback(
    (href: string, url: string) => {
      // When the user types in the search bar, but doesn't submit the query, there are
      // scenarios where the search query is not in the URL. In this case, we need to
      // set the dirtySearchQuery to `href` the new search query.
      setDirtySearchQuery(href)

      navigateToUrl(url)
      setCurrentPage(1)
    },
    [navigateToUrl, setCurrentPage, setDirtySearchQuery],
  )

  const [useSearchQueryForBulk, setUseSearchQueryForBulk] = useState(false)
  const {setSelectedCount} = useListViewSelection()
  const {setMultiPageSelectionAllowed} = useListViewMultiPageSelection()

  const onToggleSelectAll = useCallback(
    (isSelectAllChecked: boolean) => {
      if (isSelectAllChecked) {
        setCheckedItems(
          issueNodes.filter(node => node != null).reduce((map, node) => map.set(node.id, node), new Map()),
        )
        updateListHasPRs(
          issueNodes.filter(node => node != null).reduce((map, node) => map.set(node.id, node), new Map()),
        )
      } else {
        setCheckedItems(new Map())
        if (useSearchQueryForBulk) {
          setUseSearchQueryForBulk(false)
          setSelectedCount(0)
          setMultiPageSelectionAllowed?.(false)
        }
      }
    },
    [
      issueNodes,
      setSelectedCount,
      setCheckedItems,
      useSearchQueryForBulk,
      setMultiPageSelectionAllowed,
      updateListHasPRs,
    ],
  )

  const issuesSearchUrl = useCallback((query?: string) => searchUrl({viewId: currentViewId, query}), [currentViewId])
  const sortAction = useMemo(
    () => ({
      key: 'sort-by',
      render: (isOverflowMenu: boolean) => {
        return (
          <SortingDropdown
            activeSearchQuery={activeSearchQuery}
            dirtySearchQuery={dirtySearchQuery || activeSearchQuery}
            setReactionEmojiToDisplay={setReactionEmojiToDisplay}
            setSortingItemSelected={setSortingItemSelected}
            searchUrl={issuesSearchUrl}
            nested={isOverflowMenu}
            setCurrentPage={setCurrentPage}
          />
        )
      },
    }),
    [
      activeSearchQuery,
      dirtySearchQuery,
      issuesSearchUrl,
      setCurrentPage,
      setReactionEmojiToDisplay,
      setSortingItemSelected,
    ],
  )

  const spinnerAction = useMemo(
    () => ({
      key: 'spinner',
      render: () => (isQueryLoading ? <Spinner size="small" /> : <></>),
    }),
    [isQueryLoading],
  )

  const filterActions: Action[] = useMemo(() => {
    if (!scoped_repository) {
      return []
    }

    const actionList = [
      {
        key: 'authors',
        render: (isOverflowMenu: boolean) => (
          <ListAuthorFilter nested={isOverflowMenu} repo={scoped_repository} applySectionFilter={applySectionFilter} />
        ),
      },
      {
        key: 'labels',
        render: (isOverflowMenu: boolean) => (
          <ListLabelFilter nested={isOverflowMenu} repo={scoped_repository} applySectionFilter={applySectionFilter} />
        ),
      },
      {
        key: 'projects',
        render: (isOverflowMenu: boolean) => (
          <ListProjectFilter nested={isOverflowMenu} repo={scoped_repository} applySectionFilter={applySectionFilter} />
        ),
      },
      {
        key: 'milestones',
        render: (isOverflowMenu: boolean) => (
          <ListMilestoneFilter
            nested={isOverflowMenu}
            repo={scoped_repository}
            applySectionFilter={applySectionFilter}
          />
        ),
      },
      {
        key: 'assignees',
        render: (isOverflowMenu: boolean) => (
          <ListAssigneeFilter
            nested={isOverflowMenu}
            repo={scoped_repository}
            applySectionFilter={applySectionFilter}
          />
        ),
      },
    ]

    if (isInOrganization) {
      actionList.push({
        key: 'issue-types',
        render: (isOverflowMenu: boolean) => (
          <ListIssueTypeFilter
            nested={isOverflowMenu}
            repo={scoped_repository}
            applySectionFilter={applySectionFilter}
          />
        ),
      })
    }

    return actionList
  }, [applySectionFilter, scoped_repository, isInOrganization])

  const allActions = useMemo(
    () => (!IS_BROWSER ? [] : [spinnerAction, ...filterActions, sortAction]),
    [filterActions, sortAction, spinnerAction],
  )
  return (
    <ListViewMetadata
      // For now, adding tabs just for issues#index
      title={!scoped_repository && results}
      sectionFilters={
        scoped_repository && (
          <OpenClosedTabs applySectionFilter={applySectionFilter} scopedRepository={scoped_repository} />
        )
      }
      onToggleSelectAll={onToggleSelectAll}
      density={'condensed'}
      assistiveAnnouncement={isQueryLoading ? LABELS.loadingQueryResults : undefined}
      actionsLabel="Actions"
      actions={allActions}
      // actions={[spinnerAction, ...filterActions, sortAction]}
      className={styles.ListViewMetadata_0}
      {...rest}
    />
  )
}

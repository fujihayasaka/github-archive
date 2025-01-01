import {SortingDropdown} from '@github-ui/list-view-items-issues-prs/SortingDropdown'
import {SortingOptionsMenu} from '@github-ui/list-view-items-issues-prs/SortingOptionsMenu'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {Spinner} from '@primer/react'
import {useCallback, useMemo, useState} from 'react'
import {useListViewSelection} from '@github-ui/list-view/ListViewSelectionContext'
import {useListViewMultiPageSelection} from '@github-ui/list-view/ListViewMultiPageSelectionContext'
import {ListViewMetadata} from '@github-ui/list-view/ListViewMetadata'
import {LABELS} from '../../../constants/labels'
import {useQueryContext, useQueryEditContext} from '../../../contexts/QueryContext'
import type {AppPayload} from '../../../types/app-payload'
import {searchUrl} from '../../../utils/urls'
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
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
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
  sortingItemSelected,
  setCheckedItems,
  setReactionEmojiToDisplay,
  setSortingItemSelected,
  setCurrentPage,
}: ListItemsHeaderProps) {
  const {scoped_repository} = useAppPayload<AppPayload>()
  const {dirtySearchQuery} = useQueryEditContext()
  const {activeSearchQuery, isQueryLoading, currentViewId} = useQueryContext()
  const {issue_types, issues_react_new_sort_dropdown, issues_react_csr_index_actions} = useFeatureFlags()
  const {navigateToUrl} = useAppNavigate()
  const results = useMemo(() => LABELS.numberOfResults(issueCount), [issueCount])

  const applySectionFilter = useCallback(
    (href: string, url: string) => {
      navigateToUrl(url)
      setCurrentPage(1)
    },
    [navigateToUrl, setCurrentPage],
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
      } else {
        setCheckedItems(new Map())
        if (useSearchQueryForBulk) {
          setUseSearchQueryForBulk(false)
          setSelectedCount(0)
          setMultiPageSelectionAllowed?.(false)
        }
      }
    },
    [issueNodes, setSelectedCount, setCheckedItems, useSearchQueryForBulk, setMultiPageSelectionAllowed],
  )

  const issuesSearchUrl = useCallback((query?: string) => searchUrl({viewId: currentViewId, query}), [currentViewId])
  const sortAction = useMemo(
    () => ({
      key: 'sort-by',
      render: (isOverflowMenu: boolean) => {
        if (issues_react_new_sort_dropdown) {
          return (
            <SortingDropdown
              activeSearchQuery={activeSearchQuery}
              dirtySearchQuery={dirtySearchQuery}
              setReactionEmojiToDisplay={setReactionEmojiToDisplay}
              setSortingItemSelected={setSortingItemSelected}
              searchUrl={issuesSearchUrl}
              nested={isOverflowMenu}
              setCurrentPage={setCurrentPage}
            />
          )
        } else {
          return (
            <SortingOptionsMenu
              activeSearchQuery={activeSearchQuery}
              dirtySearchQuery={dirtySearchQuery}
              setReactionEmojiToDisplay={setReactionEmojiToDisplay}
              setSortingItemSelected={setSortingItemSelected}
              sortingItemSelected={sortingItemSelected}
              searchUrl={issuesSearchUrl}
              nested={isOverflowMenu}
            />
          )
        }
      },
    }),
    [
      activeSearchQuery,
      dirtySearchQuery,
      issuesSearchUrl,
      issues_react_new_sort_dropdown,
      setCurrentPage,
      setReactionEmojiToDisplay,
      setSortingItemSelected,
      sortingItemSelected,
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

    if (issue_types) {
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
  }, [applySectionFilter, scoped_repository, issue_types])

  const allActions = useMemo(
    () => (issues_react_csr_index_actions && !IS_BROWSER ? [] : [spinnerAction, ...filterActions, sortAction]),
    [filterActions, issues_react_csr_index_actions, sortAction, spinnerAction],
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
    />
  )
}

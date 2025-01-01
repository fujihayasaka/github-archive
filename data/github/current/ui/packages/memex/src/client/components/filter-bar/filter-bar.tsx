import {Filter} from '@github-ui/filter'
import {IssueTypeFilterProvider} from '@github-ui/issue-type-filter-provider'
import {type ColorName, type ColorSet, useGetPresentationalColor} from '@github-ui/use-named-color'
import {memo, useCallback, useMemo, useRef} from 'react'
import {type Environment, useRelayEnvironment} from 'react-relay'

import {MemexColumnDataType} from '../../api/columns/contracts/memex-column'
import {assertNever} from '../../helpers/assert-never'
import {getInitialState} from '../../helpers/initial-state'
import type {LoggedInUser} from '../../helpers/json-island'
import {useEnabledFeatures} from '../../hooks/use-enabled-features'
import {isFilterableColumn} from '../../models/column-capabilities'
import type {ColumnModel} from '../../models/column-model'
import {useAllColumns} from '../../state-providers/columns/use-all-columns'
import {Resources} from '../../strings'
import styles from './filter-bar.module.css'
import {
  DateFilterProvider,
  FILTER_PRIORITIES,
  IterationFilterProvider,
  LastUpdatedFilterProvider,
  LinkedPullRequestsFilterProvider,
  MemexAssigneeFilterProvider,
  MemexIsFilterProvider,
  MemexLabelFilterProvider,
  MemexMilestoneFilterProvider,
  MemexParentIssueFilterProvider,
  MemexRepositoryFilterProvider,
  MemexReviewersFilterProvider,
  MemexStateFilterProvider,
  MemexUpdatedFilterProvider,
  NumberFilterProvider,
  ReasonFilterProvider,
  SingleSelectFilterProvider,
  SubIssuesProgressFilterProvider,
  TextFilterProvider,
  TitleFilterProvider,
} from './filter-providers'
import {useHandleFilterBarShortcut} from './use-handle-filter-bar-shortcut'

type FilterBarProps = {
  value?: string
  onChange: (value: string) => void
}

const getFilterProviderForColumn = (
  column: ColumnModel,
  getPresentationalColor: (color: ColorName) => ColorSet,
  loggedInUser?: LoggedInUser,
  relayEnvironment?: Environment,
  projectOwnerLogin?: string,
  projectNumber?: number,
) => {
  const userFilterParams = loggedInUser
    ? {
        showAtMe: true,
        currentUserLogin: loggedInUser.login,
        currentUserAvatarUrl: loggedInUser.avatarUrl,
      }
    : {showAtMe: false}

  if (!isFilterableColumn(column.dataType)) {
    return undefined
  }
  switch (column.dataType) {
    case MemexColumnDataType.Assignees:
      return new MemexAssigneeFilterProvider(column, userFilterParams, {
        filterTypes: {exclusive: true, hasValue: true},
      })
    case MemexColumnDataType.Date:
      return new DateFilterProvider(column)
    case MemexColumnDataType.Iteration:
      return new IterationFilterProvider(column)
    case MemexColumnDataType.Labels:
      return new MemexLabelFilterProvider(column, {
        filterTypes: {exclusive: true, hasValue: true},
      })
    case MemexColumnDataType.LinkedPullRequests:
      return new LinkedPullRequestsFilterProvider({
        filterTypes: {hasValue: true},
      })
    case MemexColumnDataType.Milestone:
      return new MemexMilestoneFilterProvider(column, {
        priority: FILTER_PRIORITIES.milestone,
        filterTypes: {exclusive: true, hasValue: true},
      })
    case MemexColumnDataType.IssueType:
      return new IssueTypeFilterProvider(
        {priority: FILTER_PRIORITIES.type, filterTypes: {valueless: true, hasValue: true}},
        false,
        relayEnvironment,
        undefined,
        {login: projectOwnerLogin, projectNumber},
      )
    case MemexColumnDataType.Number:
      return new NumberFilterProvider(column)
    case MemexColumnDataType.Repository:
      return new MemexRepositoryFilterProvider(column, {filterTypes: {exclusive: true, hasValue: true}})
    case MemexColumnDataType.Reviewers:
      return new MemexReviewersFilterProvider(userFilterParams, {
        filterTypes: {exclusive: true, hasValue: true},
      })
    case MemexColumnDataType.SingleSelect:
      return new SingleSelectFilterProvider(column, getPresentationalColor)
    case MemexColumnDataType.SubIssuesProgress:
      return new SubIssuesProgressFilterProvider(column, {filterTypes: {hasValue: true}})
    case MemexColumnDataType.Text:
      return new TextFilterProvider(column)
    case MemexColumnDataType.Title:
      return new TitleFilterProvider(column)
    case MemexColumnDataType.ParentIssue:
      return new MemexParentIssueFilterProvider(column, {filterTypes: {hasValue: true}})
    default:
      assertNever(column.dataType)
  }
}

export const FilterBar = memo(function FilterBar({value, onChange}: FilterBarProps) {
  const relayEnvironment = useRelayEnvironment()

  const {memex_table_without_limits} = useEnabledFeatures()
  const {allColumns} = useAllColumns()
  const {loggedInUser, projectOwner, projectData} = getInitialState()
  const {getPresentationalColor} = useGetPresentationalColor()
  const columnFilterProviders = useMemo(() => {
    return allColumns
      .map(column =>
        getFilterProviderForColumn(
          column,
          getPresentationalColor,
          loggedInUser,
          relayEnvironment,
          projectOwner?.login,
          projectData?.number,
        ),
      )
      .filter(p => !!p)
  }, [allColumns, loggedInUser, relayEnvironment, projectOwner?.login, projectData?.number, getPresentationalColor])

  const inputRef = useRef<HTMLInputElement>(null)

  const onFilterBarShortcut = useCallback(() => {
    inputRef.current?.focus()
  }, [])

  useHandleFilterBarShortcut(onFilterBarShortcut)

  return (
    <Filter
      id="filter-bar-component"
      data-testid="filter-bar-component"
      label="Filter"
      filterButtonVariant="compact"
      settings={{
        aliasMatching: true,
      }}
      variant={memex_table_without_limits ? 'input' : 'full'}
      aria-label={Resources.filterByKeyboardOrByField}
      placeholder={Resources.filterByKeyboardOrByField}
      filterValue={value}
      inputRef={inputRef}
      onChange={onChange}
      providers={useMemo(
        () => [
          ...columnFilterProviders,
          new LastUpdatedFilterProvider(),
          new MemexIsFilterProvider(['issue', 'pr', 'open', 'closed', 'draft', 'merged'], {
            filterTypes: {valueless: false},
          }),
          new MemexStateFilterProvider('mixed', {
            priority: FILTER_PRIORITIES.state,
            filterTypes: {valueless: false},
          }),
          new MemexUpdatedFilterProvider({filterTypes: {valueless: false}}),
          new ReasonFilterProvider(),
        ],
        [columnFilterProviders],
      )}
      className={styles.Filter_0}
    />
  )
})

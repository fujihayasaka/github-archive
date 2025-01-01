import type {ItemIdentifier} from '@github-ui/issue-viewer/Types'
import {useRef} from 'react'
import {graphql, useFragment} from 'react-relay'

import {useQueryContext} from '../../contexts/QueryContext'
import NewViewExperience from '../list/NewViewExperience'
import {SearchBar} from '../search/SearchBar'
import {SearchList} from '../search/SearchList'

import {SingleSignOnBanner} from '@github-ui/single-sign-on-banner'
import {useSso} from '@github-ui/use-sso'
import type {LoadSearchQuery} from '../../pages/shared'
import type {DashboardSearchCurrentViewFragment$key} from './__generated__/DashboardSearchCurrentViewFragment.graphql'
import type {DashboardSearchFragment$key} from './__generated__/DashboardSearchFragment.graphql'
import {DashboardEditViewActions} from './DashboardEditViewActions'
import {DashboardSearchBarActions} from './DashboardSearchBarActions'
import styles from './DashboardSearch.module.css'

type DashboardSearchProps = {
  itemIdentifier: ItemIdentifier | undefined
  currentView: DashboardSearchCurrentViewFragment$key
  search: DashboardSearchFragment$key
  loadSearchQuery?: LoadSearchQuery
  onSidePanelNavigate?: (issue: ItemIdentifier) => void
}

const DashboardSearchFragment = graphql`
  fragment DashboardSearchFragment on Searchable
  @argumentDefinitions(
    query: {type: "String!"}
    first: {type: "Int"}
    labelPageSize: {type: "Int!"}
    skip: {type: "Int", defaultValue: null}
    fetchRepository: {type: "Boolean!"}
  ) {
    ...SearchList
      @arguments(
        query: $query
        first: $first
        labelPageSize: $labelPageSize
        fetchRepository: $fetchRepository
        skip: $skip
      )
  }
`

const CurrentViewFragment = graphql`
  fragment DashboardSearchCurrentViewFragment on Shortcutable {
    query
    ...DashboardSearchBarActionsFragment
    ...DashboardEditViewActionsFragment
    ...SearchBarCurrentViewFragment
  }
`

export function DashboardSearch({
  itemIdentifier,
  currentView,
  search,
  loadSearchQuery,
  onSidePanelNavigate,
}: DashboardSearchProps) {
  const {ssoOrgs} = useSso()
  const orgNames = ssoOrgs.map(o => o['login']).filter(n => n !== undefined)

  const searchListData = useFragment(DashboardSearchFragment, search)
  const currentViewData = useFragment(CurrentViewFragment, currentView)

  const {activeSearchQuery, isNewView, isEditing} = useQueryContext()

  const listRef = useRef<HTMLUListElement | undefined>(undefined)

  const showNewViewExperience = isNewView && !activeSearchQuery

  const actionsComponent = isEditing ? (
    <DashboardEditViewActions currentView={currentViewData} />
  ) : (
    <DashboardSearchBarActions currentView={currentViewData} />
  )

  return (
    <div className={styles.searchContainer}>
      <SearchBar currentViewKey={currentViewData} currentRepository={null} queryFromCustomView={currentViewData.query}>
        <div className={styles.actions}>{actionsComponent}</div>
      </SearchBar>
      {showNewViewExperience ? (
        <NewViewExperience />
      ) : (
        <>
          <SingleSignOnBanner protectedOrgs={orgNames} />
          <SearchList
            itemIdentifier={itemIdentifier}
            search={searchListData}
            repository={null}
            loadSearchQuery={loadSearchQuery}
            query={activeSearchQuery}
            listRef={listRef}
            onSidePanelNavigate={onSidePanelNavigate}
          />
        </>
      )}
    </div>
  )
}

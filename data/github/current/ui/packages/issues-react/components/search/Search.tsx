import type {ItemIdentifier} from '@github-ui/issue-viewer/Types'
import {Box} from '@primer/react'
import {useRef} from 'react'
import {graphql, useFragment} from 'react-relay'

import {useQueryContext} from '../../contexts/QueryContext'
import NewViewExperience from '../list/NewViewExperience'
import type {SearchBarCurrentViewFragment$key} from './__generated__/SearchBarCurrentViewFragment.graphql'
import {SearchBar} from './SearchBar'
import {SearchList} from './SearchList'

import type {LoadSearchQuery} from '../../pages/shared'
import type {SearchRepositoryFragment$key} from './__generated__/SearchRepositoryFragment.graphql'
import type {SearchRootFragment$key} from './__generated__/SearchRootFragment.graphql'

type SearchProps = {
  itemIdentifier: ItemIdentifier | undefined
  currentView: SearchBarCurrentViewFragment$key
  currentRepository: SearchRepositoryFragment$key | null
  search: SearchRootFragment$key
  loadSearchQuery?: LoadSearchQuery
  queryFromCustomView?: string | null
  onSidePanelNavigate?: (issue: ItemIdentifier) => void
}

export function Search({
  itemIdentifier,
  currentView,
  currentRepository,
  search,
  loadSearchQuery,
  queryFromCustomView,
  onSidePanelNavigate,
}: SearchProps) {
  const data = useFragment(
    graphql`
      fragment SearchRootFragment on Searchable
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
    `,
    search,
  )

  const repoData = useFragment(
    graphql`
      fragment SearchRepositoryFragment on Repository {
        ...SearchBarActionsRepositoryFragment
        ...SearchListRepo
      }
    `,
    currentRepository,
  )

  const {activeSearchQuery, isNewView} = useQueryContext()

  const listRef = useRef<HTMLUListElement | undefined>(undefined)

  return (
    <Box sx={{display: 'flex', flexDirection: 'column', gap: 3}}>
      <SearchBar
        currentView={currentView}
        currentRepository={repoData ?? null}
        queryFromCustomView={queryFromCustomView}
      />
      {isNewView && !activeSearchQuery ? (
        <NewViewExperience />
      ) : (
        <SearchList
          itemIdentifier={itemIdentifier}
          search={data}
          repository={repoData ?? null}
          loadSearchQuery={loadSearchQuery}
          query={activeSearchQuery}
          queryFromCustomView={queryFromCustomView}
          listRef={listRef}
          onSidePanelNavigate={onSidePanelNavigate}
        />
      )}
    </Box>
  )
}

import {Box} from '@primer/react'
import {memo, Suspense} from 'react'
import {graphql, useFragment} from 'react-relay'

import type {ItemIdentifier} from '@github-ui/issue-viewer/Types'
import {Header} from '../components/list/header/Header'
import {HeaderLoading} from '../components/list/header/HeaderLoading'
import {Search} from '../components/search/Search'
import {useRouteInfo} from '../hooks/use-route-info'
import type {ListCurrentViewFragment$key} from './__generated__/ListCurrentViewFragment.graphql'
import type {ListQuery$key} from './__generated__/ListQuery.graphql'
import type {ListRepositoryFragment$key} from './__generated__/ListRepositoryFragment.graphql'
import type {LoadSearchQuery} from './shared'

export type ListProps = {
  fetchedView: ListCurrentViewFragment$key
  queryFromCustomView?: string | null
  onSidePanelNavigate?: (issue: ItemIdentifier) => void
  showSsoBanner?: boolean
  fetchedRepository: ListRepositoryFragment$key | null
  search?: ListQuery$key
  loadSearchQuery?: LoadSearchQuery
  onCollapse?: () => void
}

const ListInternal = ({
  fetchedView,
  fetchedRepository,
  search,
  loadSearchQuery,
  queryFromCustomView,
  onCollapse,
  onSidePanelNavigate,
  showSsoBanner,
}: ListProps) => {
  const currentViewData = useFragment<ListCurrentViewFragment$key>(
    graphql`
      fragment ListCurrentViewFragment on Shortcutable {
        ...SearchCurrentViewFragment
        ...HeaderCurrentViewFragment
      }
    `,
    fetchedView,
  )

  const repoData = useFragment<ListRepositoryFragment$key>(
    graphql`
      fragment ListRepositoryFragment on Repository {
        ...SearchRepositoryFragment
        ...HeaderCurrentRepositoryFragment
      }
    `,
    fetchedRepository || null,
  )

  const searchData = useFragment(
    graphql`
      fragment ListQuery on Searchable
      @argumentDefinitions(
        query: {type: "String!"}
        first: {type: "Int"}
        labelPageSize: {type: "Int!"}
        skip: {type: "Int", defaultValue: null}
        fetchRepository: {type: "Boolean!"}
      ) {
        ...SearchRootFragment
          @arguments(
            query: $query
            first: $first
            labelPageSize: $labelPageSize
            skip: $skip
            fetchRepository: $fetchRepository
          )
      }
    `,
    search,
  )

  const {itemIdentifier} = useRouteInfo()

  return (
    <Box
      sx={{
        display: 'flex',
        flexDirection: 'column',
        gap: 2,
        maxWidth: '100%',
      }}
    >
      {currentViewData && (
        <Suspense fallback={<HeaderLoading />}>
          <Header
            setSafeDocumentTitle={!!itemIdentifier?.number}
            currentViewKey={currentViewData}
            currentRepository={repoData ?? null}
            onCollapse={onCollapse}
          />
        </Suspense>
      )}
      {currentViewData && searchData && (
        <Search
          itemIdentifier={itemIdentifier}
          currentViewKey={currentViewData}
          currentRepository={repoData ?? null}
          search={searchData}
          loadSearchQuery={loadSearchQuery}
          queryFromCustomView={queryFromCustomView}
          onSidePanelNavigate={onSidePanelNavigate}
          showSsoBanner={showSsoBanner}
        />
      )}
    </Box>
  )
}

export const List = memo(ListInternal)

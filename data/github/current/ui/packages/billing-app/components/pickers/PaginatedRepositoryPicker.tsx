/* eslint relay/unused-fields: off */
import {LockIcon, RepoIcon, RepoLockedIcon, TriangleDownIcon} from '@primer/octicons-react'
import {Button, Box, Text, FormControl} from '@primer/react'
import Pluralize from 'pluralize'
import {useCallback} from 'react'
import type {PreloadedQuery} from 'react-relay'
import {graphql, usePaginationFragment, usePreloadedQuery} from 'react-relay'
import {PickerDialog} from './PickerDialog'
import {PickerHeader} from './PickerHeader'
import {SelectedRows} from './SelectedRows'
import {Fonts, Spacing} from '../../utils'
import {Banner} from '@primer/react/experimental'

import type {RepositoryPickerFragment$data} from './__generated__/RepositoryPickerFragment.graphql'
import type {PaginatedRepositoryPickerGraphqlQuery} from './__generated__/PaginatedRepositoryPickerGraphqlQuery.graphql'
import type {PaginatedRepositoryListQuery} from './__generated__/PaginatedRepositoryListQuery.graphql'
import type {
  PaginatedRepositoryPickerRepos$data,
  PaginatedRepositoryPickerRepos$key,
} from './__generated__/PaginatedRepositoryPickerRepos.graphql'
import {PaginatedPicker, PAGE_SIZE, SELECTED_ITEMS_PAGE_SIZE} from './PaginatedPicker'
import ResourcePaginator from './ResourcePaginator'

export type Repository = RepositoryPickerFragment$data

export const PaginatedRepositoryPickerParentGraphqlQuery = graphql`
  query PaginatedRepositoryPickerGraphqlQuery($slug: String!, $phrase: String) {
    viewer {
      ...PaginatedRepositoryPickerRepos @arguments(phrase: $phrase, slug: $slug, excludeArchived: true)
    }
  }
`

export const PaginatedRepositoryPickerFetchedByIDQuery = graphql`
  query PaginatedRepositoryPickerFetchedByIDQuery($ids: [ID!]!) {
    nodes(ids: $ids) {
      # eslint-disable-next-line relay/must-colocate-fragment-spreads
      ...RepositoryPickerFragment @dangerously_unaliased_fixme
      __typename
    }
  }
`

// BATCH_SIZE=100. @argumentDefinitions must be literals
const PaginatedReposGraphqlQuery = (repositoriesRef: PaginatedRepositoryPickerRepos$key) => {
  const {data, loadNext, isLoadingNext, hasNext, refetch} = usePaginationFragment<
    PaginatedRepositoryListQuery,
    PaginatedRepositoryPickerRepos$key
  >(
    graphql`
      fragment PaginatedRepositoryPickerRepos on User
      @argumentDefinitions(
        first: {type: "Int", defaultValue: 100}
        after: {type: "String"}
        phrase: {type: "String"}
        slug: {type: "String!"}
        excludeArchived: {type: "Boolean", defaultValue: true}
      )
      @refetchable(queryName: "PaginatedRepositoryListQuery") {
        enterpriseRepositories(
          first: $first
          after: $after
          phrase: $phrase
          slug: $slug
          orderBy: {field: CREATED_AT, direction: DESC}
          excludeArchived: $excludeArchived
        ) @connection(key: "PaginatedRepositoryListFragment_enterpriseRepositories") {
          edges {
            node {
              # eslint-disable-next-line relay/must-colocate-fragment-spreads
              ...RepositoryPickerFragment
            }
          }
          totalCount
        }
      }
    `,
    repositoriesRef,
  )
  return {data, loadNext, isLoadingNext, hasNext, refetch}
}

interface Props {
  initialSelectedItemIds: string[]
  preloadedRepositoriesRef: PreloadedQuery<PaginatedRepositoryPickerGraphqlQuery>
  setSelectedItems: (selectedIds: string[]) => void
  slug: string
  entityType?: 'budget' | 'cost center'
  indent?: boolean
  selectionVariant?: 'multiple' | 'single'
  valid?: boolean
  viewOnly?: boolean
}

export function PaginatedRepositoryPicker({
  initialSelectedItemIds,
  preloadedRepositoriesRef,
  setSelectedItems,
  entityType = 'budget',
  indent = true,
  selectionVariant,
  valid,
  viewOnly = false,
}: Props) {
  const convertToItemProps = useCallback(
    (item: Repository) => {
      return {
        id: item.id,
        text: item.nameWithOwner,
        leadingVisual: () => (item.isPrivate ? <LockIcon /> : <RepoIcon />),
        rowLeadingVisual: () => (item.isPrivate ? <RepoLockedIcon /> : <RepoIcon />),
        viewOnly,
      }
    },
    [viewOnly],
  )

  const preloadedData = usePreloadedQuery(PaginatedRepositoryPickerParentGraphqlQuery, preloadedRepositoriesRef)
  const dataRef = preloadedData.viewer

  const {
    localSelected,
    selectedCount,
    selectAll,
    open,
    pageCount,
    currentPage,
    error,
    items,
    onPageChange,
    filterItems,
    onDialogSubmit,
    resetDialog,
    openDialog,
    removeOption,
    totalItemCount,
    itemsLoading,
    onSelectedItemsPageChange,
    selectedItemsPageCount,
    selectedItemsCurrentPage,
    pagedSelectedItems,
  } = PaginatedPicker<Repository, PaginatedRepositoryPickerRepos$key, PaginatedRepositoryPickerRepos$data>({
    initialSelectedItemIds,
    dataRef,
    convertToItemProps,
    setSelectedItems,
    paginatedQuery: ref => {
      const {data, loadNext, isLoadingNext, hasNext, refetch} = PaginatedReposGraphqlQuery(ref)
      return {
        data,
        loadNext: (count: number) => {
          loadNext(count)
        },
        isLoadingNext,
        hasNext,
        refetch,
      }
    },
    selectedItemsFetchQuery: PaginatedRepositoryPickerFetchedByIDQuery,
    searchParamName: 'phrase',
  })

  const pickerText = selectionVariant === 'multiple' ? 'repositories' : 'repository'
  const ml = indent ? 4 : 0

  return (
    <>
      <PickerHeader title="Repositories" />
      <Box sx={{ml, textAlign: 'left'}}>
        {error && <Banner variant="critical" title={error} />}
        {!viewOnly && (
          <>
            <Button onClick={openDialog} sx={{mb: Spacing.StandardPadding}} trailingAction={TriangleDownIcon}>
              Select {pickerText}
            </Button>
            <PickerDialog
              open={open}
              resetDialog={resetDialog}
              filter={filterItems}
              selectAll={selectAll}
              selected={localSelected}
              onDialogSubmit={onDialogSubmit}
              items={items || []}
              totalItemsCount={totalItemCount}
              pickerType={pickerText}
              loading={false}
              selectionVariant={selectionVariant}
              entityType={entityType}
              pageSize={PAGE_SIZE}
              pageCount={pageCount}
              currentPage={currentPage}
              onPageChange={onPageChange}
              showPaginatedItems
            />
            {valid === false && (
              <FormControl.Validation variant="error" sx={{mt: 1}}>
                Please select at least one repository
              </FormControl.Validation>
            )}
          </>
        )}
        {selectAll && (
          <Text sx={{fontSize: Fonts.FontSizeSmall}}>All {Pluralize('repository', totalItemCount, true)} selected</Text>
        )}
        <SelectedRows
          loading={itemsLoading}
          removeOption={removeOption}
          selected={pagedSelectedItems}
          totalCount={selectedCount}
        />
        <ResourcePaginator
          pageSize={SELECTED_ITEMS_PAGE_SIZE}
          pageCount={selectedItemsPageCount}
          totalResources={selectedCount}
          currentPage={selectedItemsCurrentPage}
          onPageChange={onSelectedItemsPageChange}
        />
      </Box>
    </>
  )
}

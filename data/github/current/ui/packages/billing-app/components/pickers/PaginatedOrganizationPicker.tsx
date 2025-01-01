/* eslint relay/unused-fields: off */
import {GitHubAvatar} from '@github-ui/github-avatar'
import {TriangleDownIcon} from '@primer/octicons-react'
import {Button, Box, Text, FormControl} from '@primer/react'
import Pluralize from 'pluralize'
import {useCallback} from 'react'
import {graphql, usePaginationFragment, usePreloadedQuery, type PreloadedQuery} from 'react-relay'

import {Fonts, Spacing} from '../../utils'
import {SelectedRows} from './SelectedRows'
import {PickerDialog} from './PickerDialog'
import {PickerHeader} from './PickerHeader'
import type {OrganizationPickerFragment$data} from './__generated__/OrganizationPickerFragment.graphql'
import type {
  PaginatedOrganizationPickerOrgs$data,
  PaginatedOrganizationPickerOrgs$key,
} from './__generated__/PaginatedOrganizationPickerOrgs.graphql'
import type {PaginatedOrganizationListQuery} from './__generated__/PaginatedOrganizationListQuery.graphql'
import type {PaginatedOrganizationPickerGraphqlQuery} from './__generated__/PaginatedOrganizationPickerGraphqlQuery.graphql'
import {Banner} from '@primer/react/experimental'
import {PAGE_SIZE, PaginatedPicker, SELECTED_ITEMS_PAGE_SIZE} from './PaginatedPicker'
import ResourcePaginator from './ResourcePaginator'

type Organization = OrganizationPickerFragment$data

export const OrganizationPickerParentGraphqlQuery = graphql`
  query PaginatedOrganizationPickerGraphqlQuery($slug: String!, $query: String) {
    enterprise(slug: $slug) {
      ...PaginatedOrganizationPickerOrgs @arguments(query: $query)
    }
  }
`

export const PaginatedOrganizationPickerFetchedByIDQuery = graphql`
  query PaginatedOrganizationPickerFetchedByIDQuery($ids: [ID!]!) {
    nodes(ids: $ids) {
      # eslint-disable-next-line relay/must-colocate-fragment-spreads
      ...OrganizationPickerFragment @dangerously_unaliased_fixme
      __typename
    }
  }
`

// BATCH_SIZE=100. @argumentDefinitions must be literals
const PaginatedOrgsGraphqlQuery = (organizationsRef: PaginatedOrganizationPickerOrgs$key) => {
  const {data, loadNext, isLoadingNext, hasNext, refetch} = usePaginationFragment<
    PaginatedOrganizationListQuery,
    PaginatedOrganizationPickerOrgs$key
  >(
    graphql`
      fragment PaginatedOrganizationPickerOrgs on Enterprise
      @argumentDefinitions(first: {type: "Int", defaultValue: 100}, after: {type: "String"}, query: {type: "String"})
      @refetchable(queryName: "PaginatedOrganizationListQuery") {
        organizations(first: $first, after: $after, query: $query, orderBy: {field: CREATED_AT, direction: DESC})
          @connection(key: "PaginatedOrganizationListFragment_organizations") {
          edges {
            node {
              # eslint-disable-next-line relay/must-colocate-fragment-spreads
              ...OrganizationPickerFragment
            }
          }
          totalCount
        }
      }
    `,
    organizationsRef,
  )
  return {data, loadNext, isLoadingNext, hasNext, refetch}
}

interface Props {
  initialSelectedItemIds: string[]
  preloadedOrganizationsRef: PreloadedQuery<PaginatedOrganizationPickerGraphqlQuery>
  setSelectedItems: (selectedIds: string[]) => void
  entityType?: 'budget' | 'cost center'
  indent?: boolean
  selectionVariant?: 'multiple' | 'single'
  valid?: boolean
  // Optionally display the picker in view-only mode
  viewOnly?: boolean
}

export function PaginatedOrganizationPicker({
  initialSelectedItemIds,
  preloadedOrganizationsRef,
  setSelectedItems,
  entityType = 'budget',
  indent = true,
  selectionVariant,
  valid,
  viewOnly = false,
}: Props) {
  const convertToItemProps = useCallback(
    (item: Organization) => {
      return {
        id: item.id,
        text: item.login,
        leadingVisual: () => <GitHubAvatar square src={item.avatarUrl} alt="Organizations login" />,
        rowLeadingVisual: () => <GitHubAvatar square src={item.avatarUrl} alt="Organizations login" />,
        viewOnly,
      }
    },
    [viewOnly],
  )

  const preloadedData = usePreloadedQuery(OrganizationPickerParentGraphqlQuery, preloadedOrganizationsRef)
  const dataRef = preloadedData.enterprise

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
  } = PaginatedPicker<Organization, PaginatedOrganizationPickerOrgs$key, PaginatedOrganizationPickerOrgs$data>({
    initialSelectedItemIds,
    dataRef,
    convertToItemProps,
    setSelectedItems,
    paginatedQuery: ref => {
      const {data, loadNext, isLoadingNext, hasNext, refetch} = PaginatedOrgsGraphqlQuery(ref)
      return {
        data,
        loadNext: (count: number) => loadNext(count),
        isLoadingNext,
        hasNext,
        refetch,
      }
    },
    selectedItemsFetchQuery: PaginatedOrganizationPickerFetchedByIDQuery,
    searchParamName: 'query',
  })

  const pickerText = selectionVariant === 'multiple' ? 'organizations' : 'organization'
  const ml = indent ? 4 : 0
  return (
    <>
      <PickerHeader title="Organizations" />
      <Box sx={{ml, textAlign: 'left'}}>
        {error && <Banner variant="critical" title={error} />}
        {!viewOnly && (
          <>
            <Button
              data-testid="open-org-picker-dialog-button"
              onClick={openDialog}
              sx={{mb: Spacing.StandardPadding}}
              trailingAction={TriangleDownIcon}
            >
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
                Please select at least one organization
              </FormControl.Validation>
            )}
          </>
        )}
        {selectAll && (
          <Text sx={{fontSize: Fonts.FontSizeSmall}}>
            All {Pluralize('organization', totalItemCount, true)} selected
          </Text>
        )}
        <SelectedRows
          loading={itemsLoading}
          selected={pagedSelectedItems}
          removeOption={removeOption}
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

import {GitHubAvatar} from '@github-ui/github-avatar'
import {TriangleDownIcon} from '@primer/octicons-react'
import type {Pagination} from '@primer/react'
import {Button, Box, Text, FormControl} from '@primer/react'
import Pluralize from 'pluralize'
import {useCallback, useMemo, useState, useEffect} from 'react'
import {graphql, readInlineData, usePaginationFragment, usePreloadedQuery, type PreloadedQuery} from 'react-relay'

import {Fonts, Spacing} from '../../utils'
import {SelectedRows} from './SelectedRows'
import {PickerDialog} from './PickerDialog'
import type {Item} from '../../types/common'
import {PickerHeader} from './PickerHeader'
import {OrganizationPickerFragment} from './OrganizationPicker'
import type {
  OrganizationPickerFragment$data,
  OrganizationPickerFragment$key,
} from './__generated__/OrganizationPickerFragment.graphql'
import type {PaginatedOrganizationPickerOrgs$key} from './__generated__/PaginatedOrganizationPickerOrgs.graphql'
import type {PaginatedOrganizationListQuery} from './__generated__/PaginatedOrganizationListQuery.graphql'
import type {PaginatedOrganizationPickerGraphqlQuery} from './__generated__/PaginatedOrganizationPickerGraphqlQuery.graphql'
import {Banner} from '@primer/react/experimental'

const MAX_ORG_ITEMS = 1500
const BATCH_SIZE = 100
const PAGE_SIZE = 50
type Organization = OrganizationPickerFragment$data

export const OrganizationPickerParentGraphqlQuery = graphql`
  query PaginatedOrganizationPickerGraphqlQuery($slug: String!, $query: String) {
    enterprise(slug: $slug) {
      ...PaginatedOrganizationPickerOrgs @arguments(query: $query)
    }
  }
`

// BATCH_SIZE=100. @argumentDefinitions must be literals
export function PaginatedOrgsGraphqlQuery(organizationsRef: PaginatedOrganizationPickerOrgs$key) {
  const {data, loadNext, isLoadingNext, hasNext} = usePaginationFragment<
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
              ...OrganizationPickerFragment
            }
          }
          totalCount
        }
      }
    `,
    organizationsRef,
  )
  return {data, loadNext, isLoadingNext, hasNext}
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
  const [localSelected, setLocalSelected] = useState<Array<Item<string>>>([])
  const [selectedCount, setSelectedCount] = useState<number>(initialSelectedItemIds.length)

  const [selectAll, setSelectAll] = useState<boolean>(false)
  const [open, setOpen] = useState<boolean>(false)
  const [searchFilter, setSearchFilter] = useState<string>('')

  const [pageCount, setPageCount] = useState(1)
  const [currentPage, setCurrentPage] = useState(1)
  const [pagedItems, setPagedItems] = useState<Array<Item<string>>>([])
  const [error, setError] = useState<string | null>(null)

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

  const preloadedData = usePreloadedQuery<PaginatedOrganizationPickerGraphqlQuery>(
    OrganizationPickerParentGraphqlQuery,
    preloadedOrganizationsRef,
  )

  const organizationsRef = preloadedData.enterprise

  useEffect(() => {
    if (!organizationsRef) {
      setError('Unable to load organizations. Please try again.')
    }
  }, [organizationsRef])

  const {data, loadNext, isLoadingNext, hasNext} = organizationsRef
    ? PaginatedOrgsGraphqlQuery(organizationsRef)
    : {data: null, loadNext: () => {}, isLoadingNext: false, hasNext: false}

  const totalOrganizationCount = data?.organizations?.totalCount ?? 0

  // total org items
  const fetchedOrgs = useMemo(() => {
    const nodes = (data?.organizations?.edges || []).flatMap(a =>
      // eslint-disable-next-line no-restricted-syntax
      a?.node ? [readInlineData<OrganizationPickerFragment$key>(OrganizationPickerFragment, a.node)] : [],
    )
    return nodes
  }, [data])

  const onPageChange: Parameters<typeof Pagination>[0]['onPageChange'] = (e, page) => {
    e.preventDefault()
    setCurrentPage(page)
    setPagedItems(fetchedOrgs.map(convertToItemProps).slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE))
  }

  const items = useMemo(() => {
    if (!searchFilter) return pagedItems
    return fetchedOrgs.filter(l => l.login.indexOf(searchFilter.toLowerCase()) >= 0).map(convertToItemProps)
  }, [searchFilter, pagedItems, fetchedOrgs, convertToItemProps])

  const filterItems = useCallback((value: string) => {
    setSearchFilter(value.trim())
  }, [])

  useEffect(() => {
    if (hasNext && !isLoadingNext && fetchedOrgs.length < MAX_ORG_ITEMS) {
      loadNext(BATCH_SIZE)
    } else {
      if (searchFilter) {
        setPageCount(1)
      } else {
        setPageCount(Math.ceil(totalOrganizationCount / PAGE_SIZE) || 1)
        setPagedItems(fetchedOrgs.map(convertToItemProps).slice((currentPage - 1) * PAGE_SIZE, currentPage * PAGE_SIZE))
      }
    }
  }, [hasNext, isLoadingNext, loadNext, searchFilter, currentPage, fetchedOrgs])

  const onDialogSubmit = (newSelected: Array<Item<string>>, newSelectAll: boolean) => {
    setOpen(false)
    setLocalSelected(newSelected)
    setSelectedCount(newSelected.length)
    setSelectAll(newSelectAll)
    setSelectedItems(newSelected.map(item => item.id))
  }

  const resetDialog = () => {
    setOpen(false)
    setLocalSelected(localSelected)
    setSelectedCount(localSelected.length)
    setSelectedItems(localSelected.map(item => item.id))
  }

  const openDialog = () => {
    setOpen(true)
  }

  const canRemoveOption = localSelected.length > 0
  const removeOption = (id: string) => {
    if (!canRemoveOption) return

    const newOptions = localSelected.filter(option => option.id !== id)
    setLocalSelected(newOptions)
    setSelectedCount(newOptions.length)
    setSelectedItems(newOptions.map(opt => opt.id))
  }

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
              data-testid="open-paginated-org-picker-dialog-button"
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
              totalItemsCount={totalOrganizationCount}
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
            All {Pluralize('organization', totalOrganizationCount, true)} selected
          </Text>
        )}
        <SelectedRows selected={localSelected} removeOption={removeOption} totalCount={selectedCount} />
      </Box>
    </>
  )
}

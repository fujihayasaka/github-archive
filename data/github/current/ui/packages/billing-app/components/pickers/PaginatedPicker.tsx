import {useState, useCallback, useMemo, useEffect} from 'react'
import {fetchQuery, readInlineData, useRelayEnvironment, type GraphQLTaggedNode} from 'react-relay'
import type {Item} from '../../types/common'
import {RepositoryPickerFragment} from './RepositoryPicker'
import type {Pagination} from '@primer/react'
import type {RepositoryPickerFragment$key} from './__generated__/RepositoryPickerFragment.graphql'
import type {PaginatedRepositoryPickerRepos$data} from './__generated__/PaginatedRepositoryPickerRepos.graphql'
import type {OrganizationPickerFragment$key} from './__generated__/OrganizationPickerFragment.graphql'
import {OrganizationPickerFragment} from './OrganizationPicker'
import type {PaginatedOrganizationPickerOrgs$data} from './__generated__/PaginatedOrganizationPickerOrgs.graphql'
import type {
  PaginatedOrganizationPickerFetchedByIDQuery as PaginatedOrganizationPickerFetchedByIDQueryType,
  PaginatedOrganizationPickerFetchedByIDQuery$data,
} from './__generated__/PaginatedOrganizationPickerFetchedByIDQuery.graphql'
import type {
  PaginatedRepositoryPickerFetchedByIDQuery as PaginatedRepositoryPickerFetchedByIDQueryType,
  PaginatedRepositoryPickerFetchedByIDQuery$data,
} from './__generated__/PaginatedRepositoryPickerFetchedByIDQuery.graphql'
import type {GraphQLError} from '@github-ui/fetch-graphql'
import {LockIcon, RepoLockedIcon} from '@primer/octicons-react'
import {PaginatedRepositoryPickerFetchedByIDQuery} from './PaginatedRepositoryPicker'
import {useDebounce} from '@github-ui/use-debounce'

const MAX_ITEMS = 6000
export const BATCH_SIZE = 100
export const PAGE_SIZE = 50
export const SELECTED_ITEMS_PAGE_SIZE = 10

type SelectedItemsFetchedQueryType =
  | PaginatedOrganizationPickerFetchedByIDQueryType
  | PaginatedRepositoryPickerFetchedByIDQueryType

type Props<PickerType, PickerKeyType, PickerDataType> = {
  initialSelectedItemIds: string[]
  dataRef: PickerKeyType | undefined | null
  convertToItemProps: (item: PickerType) => Item<string>
  setSelectedItems: (selectedIds: string[]) => void
  paginatedQuery: (dataRef: PickerKeyType) => {
    data: PickerDataType
    loadNext: (count: number) => void
    isLoadingNext: boolean
    hasNext: boolean
    refetch: ((variables: {phrase?: string}) => void) | ((variables: {query?: string}) => void)
  }
  selectedItemsFetchQuery: GraphQLTaggedNode
  searchParamName: 'phrase' | 'query'
}

function isPaginatedRepositoryPickerReposData(data: unknown): data is PaginatedRepositoryPickerRepos$data {
  return typeof data === 'object' && data !== null && 'enterpriseRepositories' in data
}

function isPaginatedOrganizationPickerOrgsData(data: unknown): data is PaginatedOrganizationPickerOrgs$data {
  return typeof data === 'object' && data !== null && 'organizations' in data
}

function isRepositoryQuery(query: GraphQLTaggedNode): query is typeof PaginatedRepositoryPickerFetchedByIDQuery {
  return query === PaginatedRepositoryPickerFetchedByIDQuery
}

export function PaginatedPicker<PickerType, PickerKeyType, PickerDataType>({
  initialSelectedItemIds,
  dataRef,
  convertToItemProps,
  setSelectedItems,
  paginatedQuery,
  selectedItemsFetchQuery,
  searchParamName,
}: Props<PickerType, PickerKeyType, PickerDataType>): {
  localSelected: Array<Item<string>>
  selectedCount: number
  selectAll: boolean
  open: boolean
  pageCount: number
  currentPage: number
  error: string | null
  items: Array<Item<string>>
  onPageChange: (e: React.MouseEvent, n: number) => void
  filterItems: (value: string) => void
  onDialogSubmit: (newSelected: Array<Item<string>>, newSelectAll: boolean) => void
  resetDialog: () => void
  openDialog: () => void
  removeOption: (id: string) => void
  totalItemCount: number
  itemsLoading: boolean
  onSelectedItemsPageChange: (e: React.MouseEvent, n: number) => void
  selectedItemsPageCount: number
  selectedItemsCurrentPage: number
  pagedSelectedItems: Array<Item<string>>
} {
  const [localSelected, setLocalSelected] = useState<Array<Item<string>>>([])
  const [selectedCount, setSelectedCount] = useState<number>(initialSelectedItemIds.length)
  const [itemsLoading, setItemsLoading] = useState<boolean>(false)
  const [selectAll, setSelectAll] = useState<boolean>(false)
  const [open, setOpen] = useState<boolean>(false)
  const [searchFilter, setSearchFilter] = useState<string>('')
  const [pageCount, setPageCount] = useState(1)
  const [currentPage, setCurrentPage] = useState(1)
  const [pagedItems, setPagedItems] = useState<Array<Item<string>>>([])
  const [error, setError] = useState<string | null>(null)
  const [selectedItemsPageCount, setSelectedItemsPageCount] = useState(1)
  const [selectedItemsCurrentPage, setSelectedItemsCurrentPage] = useState(1)
  const [pagedSelectedItems, setPagedSelectedItems] = useState<Array<Item<string>>>([])

  const environment = useRelayEnvironment()

  useEffect(() => {
    if (!dataRef) {
      setError('Unable to load data. Please try again.')
    }
  }, [dataRef])

  const {data, loadNext, isLoadingNext, hasNext, refetch} = dataRef
    ? paginatedQuery(dataRef)
    : {data: null, loadNext: () => {}, isLoadingNext: false, hasNext: false, refetch: () => {}}

  const fetchedItems: PickerType[] = useMemo(() => {
    if (isPaginatedRepositoryPickerReposData(data)) {
      const nodes = (data?.enterpriseRepositories?.edges || []).flatMap(a =>
        a?.node
          ? (() => {
              // eslint-disable-next-line no-restricted-syntax
              const nodeFragment = readInlineData<RepositoryPickerFragment$key>(RepositoryPickerFragment, a.node)
              return nodeFragment ? [nodeFragment as PickerType] : []
            })()
          : [],
      )
      return nodes
    }

    if (isPaginatedOrganizationPickerOrgsData(data)) {
      const nodes = (data?.organizations?.edges || []).flatMap(a =>
        a?.node
          ? (() => {
              // eslint-disable-next-line no-restricted-syntax
              const nodeFragment = readInlineData<OrganizationPickerFragment$key>(OrganizationPickerFragment, a.node)
              return nodeFragment ? [nodeFragment as PickerType] : []
            })()
          : [],
      )
      return nodes
    }
    return []
  }, [data])

  let totalItemCount = 0
  if (isPaginatedRepositoryPickerReposData(data)) {
    totalItemCount = data?.enterpriseRepositories?.totalCount || 0
  } else if (isPaginatedOrganizationPickerOrgsData(data)) {
    totalItemCount = data?.organizations?.totalCount || 0
  }

  const totalLoadedItemCount = fetchedItems.length

  useEffect(() => {
    if (!initialSelectedItemIds.length) return

    setItemsLoading(true)

    // Keep track of repo items that can't be loaded due to permissions so that we can display placeholders for them
    let unloadedItems: Array<Item<string>> = []

    const onGraphQLSuccess = (
      d: PaginatedRepositoryPickerFetchedByIDQuery$data | PaginatedOrganizationPickerFetchedByIDQuery$data,
    ) => {
      const nodes = (d.nodes || [])
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        .flatMap((node: any) => {
          if (node) {
            if (node.__typename === 'Repository') {
              // eslint-disable-next-line no-restricted-syntax
              const nodeFragment = readInlineData<RepositoryPickerFragment$key>(RepositoryPickerFragment, node)
              return nodeFragment ? [nodeFragment as PickerType] : []
            } else if (node.__typename === 'Organization') {
              // eslint-disable-next-line no-restricted-syntax
              const nodeFragment = readInlineData<OrganizationPickerFragment$key>(OrganizationPickerFragment, node)
              return nodeFragment ? [nodeFragment as PickerType] : []
            }
          }
          return []
        })
        .filter((node): node is PickerType => !!node) // Filter out undefined values

      const items = nodes.map(n => convertToItemProps(n))
      setLocalSelected([...items, ...unloadedItems])
      setItemsLoading(false)
    }

    const onGraphQLError = () => {
      setLocalSelected(unloadedItems)
      setItemsLoading(false)
    }

    /*
    queries have an argument limit of 100 node ids so we are batching them to fetch all items
    https://github.com/github/github/blob/0aeff718576cfc236cdcf082ab0bb68cbd35dca3/lib/platform/objects/query.rb#L86
    */
    const chunks: string[][] = []
    for (let i = 0; i < initialSelectedItemIds.length; i += BATCH_SIZE) {
      chunks.push(initialSelectedItemIds.slice(i, i + BATCH_SIZE))
    }

    const promises = chunks.map(chunk => {
      return new Promise<
        PaginatedRepositoryPickerFetchedByIDQuery$data | PaginatedOrganizationPickerFetchedByIDQuery$data
      >((resolve, reject) => {
        fetchQuery<SelectedItemsFetchedQueryType>(environment, selectedItemsFetchQuery, {
          ids: chunk,
        }).subscribe({
          next: d => {
            resolve(d)
          },
          error: (err: Error) => {
            // Get the indices that failed to load the first time so that we can remove them and try again with the rest.
            const invalidIndices = (err.cause as GraphQLError[]).reverse().map(e => {
              // This is always the index of the node that failed to load
              return e.path[e.path.length - 1] as number
            })

            if (isRepositoryQuery(selectedItemsFetchQuery)) {
              unloadedItems = initialSelectedItemIds
                .filter((_, idx) => invalidIndices.includes(idx))
                .map(id => {
                  return {
                    id,
                    text: 'Insufficient permission to view',
                    leadingVisual: () => <LockIcon />,
                    rowLeadingVisual: () => <RepoLockedIcon />,
                    viewOnly: true,
                  }
                })
            }

            // If there are some items that can be loaded successfully, try to load them on their own
            const updatedInitialSelectItemIds = initialSelectedItemIds.filter((_, idx) => !invalidIndices.includes(idx))
            if (updatedInitialSelectItemIds.length) {
              fetchQuery<SelectedItemsFetchedQueryType>(environment, selectedItemsFetchQuery, {
                ids: updatedInitialSelectItemIds,
              }).subscribe({
                next: onGraphQLSuccess,
                error: onGraphQLError,
              })
            } else {
              reject(err)
            }
          },
        })
      })
    })

    const loadInitialItems = async () => {
      try {
        const results = await Promise.all<
          PaginatedRepositoryPickerFetchedByIDQuery$data | PaginatedOrganizationPickerFetchedByIDQuery$data
        >(promises)
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const loadedItems = results.flatMap((r: any) => r.nodes || [])

        // Create a compatible object for onGraphQLSuccess
        const loadedItemsResult = {
          nodes: loadedItems,
        } as PaginatedRepositoryPickerFetchedByIDQuery$data | PaginatedOrganizationPickerFetchedByIDQuery$data

        onGraphQLSuccess(loadedItemsResult)
      } catch {
        onGraphQLError()
      }
    }

    loadInitialItems()

    // We only want to run this effect when first loading for an edit page.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const onPageChange: Parameters<typeof Pagination>[0]['onPageChange'] = (e, page) => {
    e.preventDefault()
    setCurrentPage(page)
    setPagedItems(fetchedItems.map(convertToItemProps).slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE))
  }

  // Update the selected items page division when the user changes pages
  useEffect(() => {
    setSelectedItemsPageCount(Math.ceil(localSelected.length / (1.0 * SELECTED_ITEMS_PAGE_SIZE)) || 1)
    setPagedSelectedItems(
      localSelected.slice(
        (selectedItemsCurrentPage - 1) * SELECTED_ITEMS_PAGE_SIZE,
        selectedItemsCurrentPage * SELECTED_ITEMS_PAGE_SIZE,
      ),
    )
  }, [localSelected, selectedItemsCurrentPage])

  const onSelectedItemsPageChange: Parameters<typeof Pagination>[0]['onPageChange'] = (e, page) => {
    e.preventDefault()
    setSelectedItemsCurrentPage(page)
  }

  const items = useMemo(() => {
    return pagedItems
  }, [pagedItems])

  const fetchSearchData = useCallback(
    (searchQuery: string) => {
      if (searchParamName === 'phrase') {
        refetch({phrase: searchQuery})
      } else {
        refetch({query: searchQuery})
      }
    },
    [refetch, searchParamName],
  )

  const debounceFetchSearch = useDebounce((nextValue: string) => {
    fetchSearchData(nextValue)
  }, 300)

  const filterItems = useCallback((value: string) => {
    setSearchFilter(value.trim())
  }, [])

  useEffect(() => {
    if (hasNext && !isLoadingNext && fetchedItems.length < MAX_ITEMS) {
      loadNext(BATCH_SIZE)
    } else {
      if (searchFilter) {
        debounceFetchSearch(searchFilter)
        setCurrentPage(1)
      } else {
        refetch({})
      }
      setPageCount(Math.ceil(totalLoadedItemCount / PAGE_SIZE) || 1)
      setPagedItems(fetchedItems.map(convertToItemProps).slice((currentPage - 1) * PAGE_SIZE, currentPage * PAGE_SIZE))
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fetchedItems, searchFilter, refetch, debounceFetchSearch])

  const onDialogSubmit = (newSelected: Array<Item<string>>, newSelectAll: boolean) => {
    setOpen(false)
    setLocalSelected(newSelected)
    setSelectedCount(newSelected.length)
    setSelectAll(newSelectAll)
    setSelectedItems(newSelected.map(opt => opt.id))
  }

  const resetDialog = () => {
    setOpen(false)
    setLocalSelected(localSelected)
    setSelectedCount(localSelected.length)
    setSelectedItems(localSelected.map(opt => opt.id))
  }

  const openDialog = () => {
    setOpen(true)
    setSearchFilter('')
    setCurrentPage(1)
    setPagedItems(fetchedItems.map(convertToItemProps).slice(0, PAGE_SIZE))
  }

  const canRemoveOption = localSelected.length > 0
  const removeOption = (id: string) => {
    if (!canRemoveOption) return

    const newOptions = localSelected.filter(option => option.id !== id)
    setLocalSelected(newOptions)
    setSelectedCount(newOptions.length)
    setSelectedItems(newOptions.map(opt => opt.id))
  }

  return {
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
  }
}

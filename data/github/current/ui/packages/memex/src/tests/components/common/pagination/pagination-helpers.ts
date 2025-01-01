import useIsVisible from '../../../../client/components/board/hooks/use-is-visible'
import {
  type PageType,
  pageTypeForSecondaryGroups,
} from '../../../../client/state-providers/memex-items/queries/query-keys'
import {
  usePaginatedMemexItemsQuery,
  type usePaginatedMemexItemsQueryReturnType,
} from '../../../../client/state-providers/memex-items/queries/use-paginated-memex-items-query'
import {asMockHook} from '../../../mocks/stub-utilities'

jest.mock('../../../../client/components/board/hooks/use-is-visible')
jest.mock('../../../../client/state-providers/memex-items/queries/use-paginated-memex-items-query')

export const setUpMockedHooks = (
  {
    isVisible,
    isFetchingNextPage,
    hasNextPage,
    hasInitialData,
    fetchNextPage,
  }: {
    isVisible: boolean
    isFetchingNextPage: boolean
    hasNextPage: boolean
    hasInitialData: boolean
    fetchNextPage: () => void
  },
  pageType: PageType,
  isCurrentlyVisible: boolean = true,
) => {
  asMockHook(useIsVisible).mockImplementation(() => ({
    isVisible,
    isCurrentlyVisible: () => isCurrentlyVisible,
  }))
  const mockResponse: Partial<usePaginatedMemexItemsQueryReturnType> = {
    hasInitialData,
  }
  if (pageType === pageTypeForSecondaryGroups) {
    mockResponse.isFetchingNextPageForSecondaryGroups = isFetchingNextPage
    mockResponse.hasNextPageForSecondaryGroups = hasNextPage
    mockResponse.fetchNextPageForSecondaryGroups = fetchNextPage
  } else {
    mockResponse.isFetchingNextPage = isFetchingNextPage
    mockResponse.hasNextPage = hasNextPage
    mockResponse.fetchNextPage = fetchNextPage
  }
  asMockHook(usePaginatedMemexItemsQuery).mockImplementation(() => mockResponse)
}

export const paginationScenarios = [
  {
    config: {
      isVisible: true,
      isFetchingNextPage: false,
      hasNextPage: true,
      hasInitialData: true,
    },
    shouldFetch: true,
  },
  {
    config: {
      isVisible: true,
      isFetchingNextPage: false,
      hasNextPage: false,
      hasInitialData: true,
    },
    shouldFetch: false,
  },
  {
    config: {
      isVisible: true,
      isFetchingNextPage: false,
      hasNextPage: true,
      hasInitialData: false,
    },
    shouldFetch: false,
  },
  {
    config: {
      isVisible: true,
      isFetchingNextPage: true,
      hasNextPage: true,
      hasInitialData: true,
    },
    shouldFetch: false,
  },
  {
    config: {
      isVisible: false,
      isFetchingNextPage: false,
      hasNextPage: true,
      hasInitialData: true,
    },
    shouldFetch: false,
  },
]

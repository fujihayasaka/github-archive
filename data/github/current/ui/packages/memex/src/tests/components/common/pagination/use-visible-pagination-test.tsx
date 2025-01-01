import {renderHook} from '@testing-library/react'

import {
  useGroupsVisiblePagination,
  useSecondaryGroupsVisiblePagination,
  useUngroupedVisiblePagination,
} from '../../../../client/components/common/use-visible-pagination'
import {
  type PageType,
  pageTypeForGroups,
  pageTypeForSecondaryGroups,
  pageTypeForUngroupedItems,
} from '../../../../client/state-providers/memex-items/queries/query-keys'
import {paginationScenarios, setUpMockedHooks} from './pagination-helpers'

jest.mock('../../../../client/components/board/hooks/use-is-visible')
jest.mock('../../../../client/state-providers/memex-items/queries/use-paginated-memex-items-query')

const mockFetchNextPage = jest.fn()

const paginationHooks = [
  {
    hook: useUngroupedVisiblePagination,
    pageType: pageTypeForUngroupedItems,
  },
  {
    hook: useGroupsVisiblePagination,
    pageType: pageTypeForGroups,
  },
  {
    hook: useSecondaryGroupsVisiblePagination,
    pageType: pageTypeForSecondaryGroups,
  },
]

describe('useVisiblePagination hooks', () => {
  for (const {config, shouldFetch} of paginationScenarios) {
    describe(`For ${JSON.stringify(config)}`, () => {
      for (const pagination of paginationHooks) {
        it(`${pagination.hook.name} should ${shouldFetch ? '' : 'not '}call fetchNextPage`, () => {
          mockFetchNextPage.mockClear()
          setUpMockedHooks({...config, fetchNextPage: mockFetchNextPage}, pagination.pageType as PageType)
          renderHook(() => pagination.hook())
          expect(mockFetchNextPage).toHaveBeenCalledTimes(shouldFetch ? 1 : 0)
        })
      }
    })
  }
  describe('when isVisible is true for two consecutive renders', () => {
    for (const pagination of paginationHooks) {
      it(`${pagination.hook.name} should call fetchNextPage again if isCurrentlyVisible is also true`, () => {
        mockFetchNextPage.mockClear()
        setUpMockedHooks(
          {
            isVisible: true,
            isFetchingNextPage: false,
            hasNextPage: true,
            hasInitialData: true,
            fetchNextPage: mockFetchNextPage,
          },
          pagination.pageType as PageType,
          true, // isCurrentlyVisible: () => true
        )
        const {rerender} = renderHook(() => pagination.hook())
        expect(mockFetchNextPage).toHaveBeenCalledTimes(1)
        rerender()
        expect(mockFetchNextPage).toHaveBeenCalledTimes(2)
      })
      it(`${pagination.hook.name} should not call fetchNextPage if isCurrentlyVisible is false`, () => {
        mockFetchNextPage.mockClear()
        setUpMockedHooks(
          {
            isVisible: true,
            isFetchingNextPage: false,
            hasNextPage: true,
            hasInitialData: true,
            fetchNextPage: mockFetchNextPage,
          },
          pagination.pageType as PageType,
          false, // isCurrentlyVisible: () => false
        )
        const {rerender} = renderHook(() => pagination.hook())
        expect(mockFetchNextPage).toHaveBeenCalledTimes(1)
        rerender()
        expect(mockFetchNextPage).toHaveBeenCalledTimes(1)
      })
    }
  })
})

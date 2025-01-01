import {act, renderHook} from '@testing-library/react'

import {useEnabledFeatures} from '../../client/hooks/use-enabled-features'
import {EagerQueryInvalidationSingleton} from '../../client/state-providers/data-refresh/eager-query-invalidation'
import {mostRecentUpdateSingleton} from '../../client/state-providers/data-refresh/most-recent-update'
import {pendingUpdatesSingleton} from '../../client/state-providers/data-refresh/pending-updates'
import {useHandlePaginatedDataRefresh} from '../../client/state-providers/data-refresh/use-handle-paginated-data-refresh'
import {
  buildMemexGroupedItemsQueryKey,
  buildMemexGroupsQueryKey,
  buildMemexSecondaryGroupsQueryKey,
  buildMemexUngroupedItemsQueryKey,
  type MemexGroupedItemsQueryKey,
  type MemexGroupsQueryKey,
  type MemexSecondaryGroupsQueryKey,
  type MemexUngroupedItemsQueryKey,
} from '../../client/state-providers/memex-items/queries/query-keys'
import {
  type PageParam,
  pageParamForInitialPage,
  pageParamForNextPlaceholder,
} from '../../client/state-providers/memex-items/queries/types'
import {usePaginatedMemexItemsQuery} from '../../client/state-providers/memex-items/queries/use-paginated-memex-items-query'
import {asMockHook} from '../mocks/stub-utilities'
import {createTestQueryClient} from '../test-app-wrapper'
import {createWrapperWithContexts} from '../wrapper-utils'

jest.mock('../../client/state-providers/memex-items/queries/use-paginated-memex-items-query')
jest.mock('../../client/hooks/use-enabled-features')

describe('useHandlePaginatedDataRefresh', () => {
  beforeEach(() => {
    asMockHook(useEnabledFeatures).mockReturnValue({memex_table_without_limits: true})
  })
  it('should cancel appropriate queries with createTestQueryClient', () => {
    const itemKeys: Array<MemexUngroupedItemsQueryKey> = []
    const groupedItemsKeys: Array<MemexGroupedItemsQueryKey> = []
    const groupKeys: Array<MemexGroupsQueryKey> = []
    const secondaryGroupKeys: Array<MemexSecondaryGroupsQueryKey> = []
    const testPageParams: Array<PageParam> = [pageParamForInitialPage, pageParamForNextPlaceholder]
    for (const pageParam of testPageParams) {
      itemKeys.push(buildMemexUngroupedItemsQueryKey({}, pageParam))
      groupedItemsKeys.push(buildMemexGroupedItemsQueryKey({}, {groupId: 'group1'}, pageParam))
      groupKeys.push(buildMemexGroupsQueryKey({}, pageParam))
      secondaryGroupKeys.push(buildMemexSecondaryGroupsQueryKey({}, pageParam))
    }
    asMockHook(usePaginatedMemexItemsQuery).mockReturnValue({
      queryKeysForGroups: groupKeys,
      queryKeysForItems: [...itemKeys, ...groupedItemsKeys],
      queryKeysForSecondaryGroups: secondaryGroupKeys,
    })

    const queryClient = createTestQueryClient()
    const spy = jest.spyOn(queryClient, 'cancelQueries')
    const {result} = renderHook(() => useHandlePaginatedDataRefresh(), {
      wrapper: createWrapperWithContexts({
        QueryClient: {
          queryClient,
        },
      }),
    })

    act(() => {
      result.current.handleCancelFetchData()
    })

    // this should only cancel non-placeholder queries
    expect(spy).toHaveBeenCalledTimes(4)
    expect(spy).toHaveBeenCalledWith({queryKey: itemKeys[0]})
    expect(spy).toHaveBeenCalledWith({queryKey: groupKeys[0]})
    expect(spy).toHaveBeenCalledWith({queryKey: groupedItemsKeys[0]})
    expect(spy).toHaveBeenCalledWith({queryKey: secondaryGroupKeys[0]})
  })

  it('should handle invalidation and cancel appropriate queries when handling refreshes', async () => {
    const groupKey = buildMemexGroupsQueryKey({}, pageParamForInitialPage)
    const invalidateAllQueriesStub = jest.fn()
    asMockHook(usePaginatedMemexItemsQuery).mockReturnValue({
      queryKeysForGroups: [groupKey],
      queryKeysForItems: [],
      queryKeysForSecondaryGroups: [],
      invalidateAllQueries: invalidateAllQueriesStub,
    })

    const queryClient = createTestQueryClient()
    const spy = jest.spyOn(queryClient, 'cancelQueries')
    const {result} = renderHook(() => useHandlePaginatedDataRefresh(), {
      wrapper: createWrapperWithContexts({
        QueryClient: {
          queryClient,
        },
      }),
    })
    await act(async () => {
      await result.current.handleRefresh()
    })

    expect(spy).toHaveBeenCalledTimes(1)
    expect(spy).toHaveBeenCalledWith({queryKey: groupKey})
    expect(invalidateAllQueriesStub).toHaveBeenCalledTimes(1)
  })

  it('should not invalidate queries when there are pending updates', async () => {
    const invalidateAllQueriesStub = jest.fn()
    asMockHook(usePaginatedMemexItemsQuery).mockReturnValue({
      queryKeysForGroups: [],
      queryKeysForItems: [],
      queryKeysForSecondaryGroups: [],
      invalidateAllQueries: invalidateAllQueriesStub,
    })

    const queryClient = createTestQueryClient()
    const {result} = renderHook(() => useHandlePaginatedDataRefresh(), {
      wrapper: createWrapperWithContexts({
        QueryClient: {
          queryClient,
        },
      }),
    })
    pendingUpdatesSingleton.increment()
    await act(async () => {
      await result.current.handleRefresh()
    })

    expect(invalidateAllQueriesStub).not.toHaveBeenCalled()
  })

  it('should not invalidate queries when the most recent update is more recent than the provided timestamp', async () => {
    const invalidateAllQueriesStub = jest.fn()
    asMockHook(usePaginatedMemexItemsQuery).mockReturnValue({
      queryKeysForGroups: [],
      queryKeysForItems: [],
      queryKeysForSecondaryGroups: [],
      invalidateAllQueries: invalidateAllQueriesStub,
    })

    const queryClient = createTestQueryClient()
    const {result} = renderHook(() => useHandlePaginatedDataRefresh(), {
      wrapper: createWrapperWithContexts({
        QueryClient: {
          queryClient,
        },
      }),
    })
    const timestamp = 100
    mostRecentUpdateSingleton.set(timestamp + 1)
    await act(async () => {
      await result.current.handleRefresh(timestamp)
    })

    expect(invalidateAllQueriesStub).not.toHaveBeenCalled()
  })

  it('should not invalidate queries that were previously eagerly invalidated', async () => {
    const invalidateAllQueriesStub = jest.fn()
    asMockHook(usePaginatedMemexItemsQuery).mockReturnValue({
      queryKeysForGroups: [],
      queryKeysForItems: [],
      queryKeysForSecondaryGroups: [],
      invalidateAllQueries: invalidateAllQueriesStub,
    })
    pendingUpdatesSingleton._reset()
    mostRecentUpdateSingleton._reset()

    const queryClient = createTestQueryClient()
    const {result} = renderHook(() => useHandlePaginatedDataRefresh(), {
      wrapper: createWrapperWithContexts({
        QueryClient: {
          queryClient,
        },
      }),
    })

    EagerQueryInvalidationSingleton.register('fake-request-id')

    await act(async () => {
      await result.current.handleRefresh(undefined, 'fake-request-id')
    })

    expect(invalidateAllQueriesStub).not.toHaveBeenCalled()
  })
})

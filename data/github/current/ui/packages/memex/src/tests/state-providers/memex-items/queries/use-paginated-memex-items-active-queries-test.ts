import {renderHook, waitFor} from '@testing-library/react'

import {type MemexProjectColumnId, SystemColumnId} from '../../../../client/api/columns/contracts/memex-column'
import {apiGetPaginatedItems} from '../../../../client/api/memex-items/api-get-paginated-items'
import {ApiError} from '../../../../client/platform/api-error'
import {
  buildGroupedItemBatchQueryKey,
  buildMemexGroupedItemsQueryKey,
  buildMemexGroupsQueryKey,
  buildMemexSecondaryGroupsQueryKey,
  buildMemexUngroupedItemsQueryKey,
} from '../../../../client/state-providers/memex-items/queries/query-keys'
import type {
  GroupedWithSecondaryGroupsPageParamsQueryData,
  PageParamsQueryData,
  PaginatedMemexItemsQueryVariables,
} from '../../../../client/state-providers/memex-items/queries/types'
import {pageParamForInitialPage} from '../../../../client/state-providers/memex-items/queries/types'
import {usePaginatedMemexItemsActiveQueries} from '../../../../client/state-providers/memex-items/queries/use-paginated-memex-items-active-queries'
import {setPageParamsQueryDataForVariables} from '../../../../client/state-providers/memex-items/query-client-api/page-params'
import {Resources} from '../../../../client/strings'
import {columnValueFactory} from '../../../factories/column-values/column-value-factory'
import {customColumnFactory} from '../../../factories/columns/custom-column-factory'
import {buildSystemColumns} from '../../../factories/columns/system-column-factory'
import {issueFactory} from '../../../factories/memex-items/issue-factory'
import {stubGetPaginatedItems} from '../../../mocks/api/memex-items'
import {createMockToastContainer} from '../../../mocks/components/toast-container'
import {createColumnsStableContext} from '../../../mocks/state-providers/columns-stable-context'
import {createTestQueryClient} from '../../../test-app-wrapper'
import {createWrapperWithContexts} from '../../../wrapper-utils'

const mockUpdateLoadedColumns = jest.fn()
jest.mock('../../../../client/state-providers/columns/use-update-loaded-columns', () => ({
  useUpdateLoadedColumnsForCurrentView: () => ({
    updateLoadedColumns: mockUpdateLoadedColumns,
  }),
}))

jest.mock('../../../../client/api/memex-items/api-get-paginated-items', () => {
  // Store original module to selectively mock only specific functions
  const originalModule = jest.requireActual('../../../../client/api/memex-items/api-get-paginated-items')

  return {
    ...originalModule,
    // Create a mockable version of the API function
    apiGetPaginatedItems: jest.fn().mockImplementation((...args) => originalModule.apiGetPaginatedItems(...args)),
  }
})

describe('usePaginatedMemexItemsActiveQueries', () => {
  it('reads from page params query data for ungrouped items', () => {
    const queryClient = createTestQueryClient()

    const variables: PaginatedMemexItemsQueryVariables = {}

    const activeQueryData: PageParamsQueryData = {
      pageParams: [pageParamForInitialPage, {after: 'firstPageEndCursor'}, {after: 'secondPageEndCursor'}],
    }

    setPageParamsQueryDataForVariables(queryClient, variables, activeQueryData)

    const {result} = renderHook(() => usePaginatedMemexItemsActiveQueries(variables), {
      wrapper: createWrapperWithContexts({
        QueryClient: {queryClient},
        ColumnsStable: createColumnsStableContext(),
        ToastContainer: createMockToastContainer(),
      }),
    })

    const {queries, queryKeys} = result.current
    const expectedQueryKeys = [
      buildMemexUngroupedItemsQueryKey(variables, pageParamForInitialPage),
      buildMemexUngroupedItemsQueryKey(variables, {after: 'firstPageEndCursor'}),
      buildMemexUngroupedItemsQueryKey(variables, {after: 'secondPageEndCursor'}),
    ]

    expect(queries).toHaveLength(3)
    expect(queryKeys).toEqual(expectedQueryKeys)
  })

  it('reads from page params query data for grouped items', () => {
    const queryClient = createTestQueryClient()

    const variables: PaginatedMemexItemsQueryVariables = {}

    const activeQueryData: PageParamsQueryData = {
      pageParams: [pageParamForInitialPage, {after: 'firstPageOfGroupsEndCursor'}],
      groupedItems: {Todo: [pageParamForInitialPage, {after: 'firstPageEndCursor'}], Done: [pageParamForInitialPage]},
    }

    setPageParamsQueryDataForVariables(queryClient, variables, activeQueryData)

    const {result} = renderHook(() => usePaginatedMemexItemsActiveQueries(variables), {
      wrapper: createWrapperWithContexts({
        QueryClient: {queryClient},
        ColumnsStable: createColumnsStableContext(),
        ToastContainer: createMockToastContainer(),
      }),
    })

    const {queries, queryKeys} = result.current
    const expectedQueryKeys = [
      buildMemexGroupedItemsQueryKey(variables, {groupId: 'Todo'}, pageParamForInitialPage),
      buildMemexGroupedItemsQueryKey(variables, {groupId: 'Todo'}, {after: 'firstPageEndCursor'}),
      buildMemexGroupedItemsQueryKey(variables, {groupId: 'Done'}, pageParamForInitialPage),
      buildMemexGroupsQueryKey(variables, pageParamForInitialPage),
      buildMemexGroupsQueryKey(variables, {after: 'firstPageOfGroupsEndCursor'}),
    ]

    expect(queries).toHaveLength(5)
    expect(queryKeys).toEqual(expectedQueryKeys)
  })

  it('reads from page params query data for grouped items with secondary groups', () => {
    const queryClient = createTestQueryClient()

    const variables: PaginatedMemexItemsQueryVariables = {}

    const activeQueryData: GroupedWithSecondaryGroupsPageParamsQueryData = {
      pageParams: [pageParamForInitialPage, {after: 'firstPageOfGroupsEndCursor'}],
      groupedItems: {Todo: [pageParamForInitialPage, {after: 'firstPageEndCursor'}], Done: [pageParamForInitialPage]},
      secondaryGroups: [pageParamForInitialPage, {after: 'firstPageOfSecondaryGroupsEndCursor'}],
      groupedItemBatches: [],
    }

    setPageParamsQueryDataForVariables(queryClient, variables, activeQueryData)

    const {result} = renderHook(() => usePaginatedMemexItemsActiveQueries(variables), {
      wrapper: createWrapperWithContexts({
        QueryClient: {queryClient},
        ColumnsStable: createColumnsStableContext(),
        ToastContainer: createMockToastContainer(),
      }),
    })

    const {queries, queryKeys, groupedItemBatchesQueries, groupedItemBatchesQueryKeys} = result.current
    const expectedQueryKeys = [
      buildMemexGroupedItemsQueryKey(variables, {groupId: 'Todo'}, pageParamForInitialPage),
      buildMemexGroupedItemsQueryKey(variables, {groupId: 'Todo'}, {after: 'firstPageEndCursor'}),
      buildMemexGroupedItemsQueryKey(variables, {groupId: 'Done'}, pageParamForInitialPage),
      buildMemexGroupsQueryKey(variables, pageParamForInitialPage),
      buildMemexGroupsQueryKey(variables, {after: 'firstPageOfGroupsEndCursor'}),
      buildMemexSecondaryGroupsQueryKey(variables, pageParamForInitialPage),
      buildMemexSecondaryGroupsQueryKey(variables, {after: 'firstPageOfSecondaryGroupsEndCursor'}),
    ]

    expect(queries).toHaveLength(7)
    expect(queryKeys).toEqual(expectedQueryKeys)
    expect(groupedItemBatchesQueries).toHaveLength(0)
    expect(groupedItemBatchesQueryKeys).toEqual([])
  })

  it('reads from page params query data for grouped items with secondary groups and grouped item batches', () => {
    const queryClient = createTestQueryClient()

    const variables: PaginatedMemexItemsQueryVariables = {}

    const activeQueryData: GroupedWithSecondaryGroupsPageParamsQueryData = {
      pageParams: [pageParamForInitialPage, {after: 'groupsCursor'}],
      secondaryGroups: [pageParamForInitialPage, {after: 'secondaryGroupsCursor'}],
      groupedItems: {'primary1:secondary1': [pageParamForInitialPage, {after: 'groupedItemsCursor'}]},
      groupedItemBatches: [{after: 'groupsCursor', secondaryAfter: 'secondaryGroupsCursor'}],
    }

    setPageParamsQueryDataForVariables(queryClient, variables, activeQueryData)

    const {result} = renderHook(() => usePaginatedMemexItemsActiveQueries(variables), {
      wrapper: createWrapperWithContexts({
        QueryClient: {queryClient},
        ColumnsStable: createColumnsStableContext(),
        ToastContainer: createMockToastContainer(),
      }),
    })

    const {queries, queryKeys, groupedItemBatchesQueries, groupedItemBatchesQueryKeys} = result.current
    const expectedQueryKeys = [
      buildMemexGroupedItemsQueryKey(
        variables,
        {groupId: 'primary1', secondaryGroupId: 'secondary1'},
        pageParamForInitialPage,
      ),
      buildMemexGroupedItemsQueryKey(
        variables,
        {groupId: 'primary1', secondaryGroupId: 'secondary1'},
        {after: 'groupedItemsCursor'},
      ),
      buildMemexGroupsQueryKey(variables, pageParamForInitialPage),
      buildMemexGroupsQueryKey(variables, {after: 'groupsCursor'}),
      buildMemexSecondaryGroupsQueryKey(variables, pageParamForInitialPage),
      buildMemexSecondaryGroupsQueryKey(variables, {after: 'secondaryGroupsCursor'}),
    ]

    const expectedGroupedItemBatchesQueryKeys = [
      buildGroupedItemBatchQueryKey(variables, {after: 'groupsCursor', secondaryAfter: 'secondaryGroupsCursor'}),
    ]

    expect(queries).toHaveLength(6)
    expect(queryKeys).toEqual(expectedQueryKeys)
    expect(groupedItemBatchesQueries).toHaveLength(1)
    expect(groupedItemBatchesQueryKeys).toEqual(expectedGroupedItemBatchesQueryKeys)
  })

  it('initializes grouped page params query data for a grouped view', () => {
    const queryClient = createTestQueryClient()

    // Seed pageParams query data for an initial ungrouped view read from the JSON island
    const activeQueryData: PageParamsQueryData = {pageParams: [pageParamForInitialPage]}
    const initialUngroupedVariables = {q: 'is:pr'}
    setPageParamsQueryDataForVariables(queryClient, initialUngroupedVariables, activeQueryData)

    // Switch to a new view grouped view.
    // The client can determine whether a view is grouped by the presence of
    // `horizontalGroupedByColumnId` or `verticalGroupedByColumnId` in the variables.
    const newGroupedVariables: PaginatedMemexItemsQueryVariables = {horizontalGroupedByColumnId: 'Status'}

    const {result} = renderHook(() => usePaginatedMemexItemsActiveQueries(newGroupedVariables), {
      wrapper: createWrapperWithContexts({
        QueryClient: {queryClient},
        ColumnsStable: createColumnsStableContext(),
        ToastContainer: createMockToastContainer(),
      }),
    })

    // If the view is grouped, we expect a query key with a grouped pageType
    const {queries, queryKeys} = result.current
    const expectedQueryKeys = [buildMemexGroupsQueryKey(newGroupedVariables, pageParamForInitialPage)]

    expect(queries).toHaveLength(1)
    expect(queryKeys).toEqual(expectedQueryKeys)
  })

  it('marks fieldIds as loaded when response is received', async () => {
    const columns = [
      ...buildSystemColumns(),
      customColumnFactory.text().build({id: 10, name: '10'}),
      customColumnFactory.text().build({id: 20, name: '20'}),
      customColumnFactory.text().build({id: 30, name: '30'}),
    ]
    const columnValues = [
      columnValueFactory.status('Todo', columns).build(),
      columnValueFactory.text('value10', '10', columns).build({memexProjectColumnId: 10}),
      columnValueFactory.text('value20', '20', columns).build({memexProjectColumnId: 20}),
      columnValueFactory.text('value30', '30', columns).build({memexProjectColumnId: 30}),
    ]
    const fieldIds: Array<MemexProjectColumnId> = [10, 20, 30, SystemColumnId.Status]
    const filteredValues = columnValues.filter(v => fieldIds.includes(v.memexProjectColumnId))
    const items = [issueFactory.withColumnValues(filteredValues).build()]
    const mockRequest = stubGetPaginatedItems({
      nodes: items,
      pageInfo: {
        startCursor: 'fake-start',
        endCursor: 'fake-end',
        hasNextPage: false,
        hasPreviousPage: false,
      },
      totalCount: {
        value: items.length,
        isApproximate: false,
      },
    })
    const queryClient = createTestQueryClient()

    // Some variables with fieldIds
    const variables = {q: 'is:pr', fieldIds}
    setPageParamsQueryDataForVariables(queryClient, variables, {pageParams: [pageParamForInitialPage]})

    renderHook(() => usePaginatedMemexItemsActiveQueries(variables), {
      wrapper: createWrapperWithContexts({
        QueryClient: {queryClient},
        ColumnsStable: createColumnsStableContext({
          loadedFieldIdsRef: {current: new Set([SystemColumnId.Status])},
        }),
        ToastContainer: createMockToastContainer(),
      }),
    })
    await waitFor(() => {
      expect(mockRequest).toHaveBeenCalledTimes(1)
    })

    expect(variables.fieldIds).toHaveLength(4)
    // It's safe to attempt to re-add Status field to the Set; it has no effect
    expect(mockUpdateLoadedColumns).toHaveBeenCalledTimes(4)
  })

  it('shows toast when response status is 503 / service unavailable', async () => {
    ;(apiGetPaginatedItems as jest.Mock).mockImplementationOnce(() => {
      throw new ApiError('Service unavailable', {status: 503})
    })

    const queryClient = createTestQueryClient()
    const toastContainer = createMockToastContainer()
    const variables = {q: 'is:pr'}

    setPageParamsQueryDataForVariables(queryClient, variables, {
      pageParams: [pageParamForInitialPage],
    })

    renderHook(() => usePaginatedMemexItemsActiveQueries(variables), {
      wrapper: createWrapperWithContexts({
        QueryClient: {queryClient},
        ColumnsStable: createColumnsStableContext(),
        ToastContainer: toastContainer,
      }),
    })

    await waitFor(() => {
      expect(toastContainer.addToast).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'error',
          message: Resources.serviceUnavailable,
        }),
      )
    })
  })
})

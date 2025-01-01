import {ClockIcon} from '@primer/octicons-react'
import {act, renderHook} from '@testing-library/react'

import {MemexColumnDataType, SystemColumnId} from '../../../client/api/columns/contracts/memex-column'
import {apiBulkUpdateItems} from '../../../client/api/memex-items/api-bulk-update-items'
import {ToastType} from '../../../client/components/toasts/types'
import {usePostStats} from '../../../client/hooks/common/use-post-stats'
import {useEnabledFeatures} from '../../../client/hooks/use-enabled-features'
import {useBulkUpdateItemColumnValues} from '../../../client/state-providers/column-values/use-bulk-update-item-column-value'
import {useFindLoadedFieldIdsForCurrentView} from '../../../client/state-providers/columns/use-find-loaded-field-ids'
import {usePaginatedMemexItemsQueryContext} from '../../../client/state-providers/memex-items/queries/paginated-memex-items-query-context'
import {useSetMemexItemData} from '../../../client/state-providers/memex-items/use-set-memex-item-data'
import {BulkUpdateResources} from '../../../client/strings'
import {getMilestoneByRepository} from '../../../mocks/data/milestones'
import {DefaultOpenIssue, DefaultOpenPullRequest} from '../../../mocks/memex-items'
import {stubRejectedApiResponse, stubResolvedApiResponse} from '../../mocks/api/memex'
import {createMockToastContainer} from '../../mocks/components/toast-container'
import {createMemexItemModel, stubSetColumnValueForItemColumnType} from '../../mocks/models/memex-item-model'
import {asMockHook} from '../../mocks/stub-utilities'
import {createWrapperWithContexts} from '../../wrapper-utils'

const LOADED_FIELD_IDS = [SystemColumnId.Title]

jest.mock('../../../client/state-providers/memex-items/use-set-memex-item-data')
jest.mock('../../../client/api/memex-items/api-bulk-update-items')
jest.mock('../../../client/hooks/common/use-post-stats')
jest.mock('../../../client/state-providers/columns/use-find-loaded-field-ids')
jest.mock('../../../client/state-providers/memex-items/queries/paginated-memex-items-query-context')
jest.mock('../../../client/hooks/use-enabled-features')

describe('useBulkUpdateItemColumnValues', () => {
  let setItemDataStub: jest.Mock
  let rerenderItemsStub: jest.Mock
  let mockPostStats: jest.Mock
  let findLoadedFieldIdsStub: jest.Mock
  let handleRefreshStub: jest.Mock

  beforeEach(() => {
    setItemDataStub = jest.fn()
    rerenderItemsStub = jest.fn()
    mockPostStats = jest.fn()
    findLoadedFieldIdsStub = jest.fn().mockReturnValue(LOADED_FIELD_IDS)
    handleRefreshStub = jest.fn()
    asMockHook(useSetMemexItemData).mockReturnValue({
      setItemData: setItemDataStub,
      setItemsStateFromModels: rerenderItemsStub,
    })
    asMockHook(usePostStats).mockReturnValue({
      postStats: mockPostStats,
    })
    asMockHook(useFindLoadedFieldIdsForCurrentView).mockReturnValue({
      findLoadedFieldIds: findLoadedFieldIdsStub,
    })

    asMockHook(usePaginatedMemexItemsQueryContext).mockReturnValue({handlePaginatedDataRefresh: handleRefreshStub})
    asMockHook(useEnabledFeatures).mockReturnValue({
      memex_table_without_limits: true,
    })
  })

  describe('bulkUpdateColumnValues', () => {
    it('should send the expected payload to the server when the new format is used for update', async () => {
      const item1 = DefaultOpenIssue
      const item2 = DefaultOpenPullRequest

      const updateColumnValueStub = stubSetColumnValueForItemColumnType()
      const memexItemModel = createMemexItemModel(item1, {
        setColumnValueForItemColumnType: updateColumnValueStub,
      })
      const memexItemModel2 = createMemexItemModel(item2, {
        setColumnValueForItemColumnType: updateColumnValueStub,
      })

      const items = [memexItemModel, memexItemModel2]

      const bulkUpdateItemsStub = stubResolvedApiResponse(apiBulkUpdateItems, {
        memexProjectItems: items,
        totalUpdatedItems: items.length,
      })

      const toastContainer = createMockToastContainer()
      const {result} = renderHook(useBulkUpdateItemColumnValues, {
        wrapper: createWrapperWithContexts({
          QueryClient: {memexItems: items},
          ToastContainer: toastContainer,
        }),
      })

      const payload = {
        dataType: MemexColumnDataType.Title,
        value: {
          title: {raw: 'some raw text', html: 'some raw text'},
        },
      }

      const itemUpdates = items.map(item => ({
        itemId: item.id,
        updates: [payload],
      }))

      await act(async () => {
        await result.current.bulkUpdateColumnValues(itemUpdates)
      })

      for (const stub of [bulkUpdateItemsStub]) {
        expect(stub).toHaveBeenCalledTimes(1)
      }

      expect(bulkUpdateItemsStub).toHaveBeenCalledWith({
        fieldIds: LOADED_FIELD_IDS,
        memexProjectItems: [
          {
            id: item1.id,
            memexProjectColumnValues: [
              {
                memexProjectColumnId: 'Title',
                value: {
                  title: 'some raw text',
                },
              },
            ],
          },
          {
            id: item2.id,
            memexProjectColumnValues: [
              {
                memexProjectColumnId: 'Title',
                value: {
                  title: 'some raw text',
                },
              },
            ],
          },
        ],
      })

      expect(mockPostStats).toHaveBeenCalledWith({
        context: 2,
        memexProjectColumnId: 'Title',
        name: 'bulk_column_value_update',
        ui: 'shortcut',
      })
    })

    it('displays a toast when the update is being processed asynchronously', async () => {
      const updateColumnValueStub = stubSetColumnValueForItemColumnType()
      const memexItemModel = createMemexItemModel(DefaultOpenIssue, {
        setColumnValueForItemColumnType: updateColumnValueStub,
      })
      const memexItemModel2 = createMemexItemModel(DefaultOpenPullRequest, {
        setColumnValueForItemColumnType: updateColumnValueStub,
      })

      const items = [memexItemModel, memexItemModel2]

      stubResolvedApiResponse(apiBulkUpdateItems, {
        memexProjectItems: [],
        totalUpdatedItems: 0,
        job: 'job-id',
        requestId: 'request-id',
      })

      const toastContainer = createMockToastContainer()
      const {result} = renderHook(useBulkUpdateItemColumnValues, {
        wrapper: createWrapperWithContexts({
          QueryClient: {memexItems: items},
          ToastContainer: toastContainer,
        }),
      })

      const itemUpdates = items.map(item => ({
        itemId: item.id,
        updates: [
          {
            dataType: MemexColumnDataType.Title,
            value: {
              title: {raw: 'some raw text', html: 'some raw text'},
            },
          },
        ],
      }))

      await act(async () => {
        await result.current.bulkUpdateColumnValues(itemUpdates)
      })

      expect(toastContainer.addPersistedToast).toHaveBeenCalledWith({
        message: BulkUpdateResources.startMessage,
        icon: ClockIcon,
        type: ToastType.default,
      })
    })

    it('should restore existing values when there are server errors', async () => {
      const item1 = DefaultOpenIssue
      const item2 = DefaultOpenPullRequest

      const updateColumnValueStub = stubSetColumnValueForItemColumnType()
      const memexItemModel = createMemexItemModel(item1, {
        setColumnValueForItemColumnType: updateColumnValueStub,
      })
      const memexItemModel2 = createMemexItemModel(item2, {
        setColumnValueForItemColumnType: updateColumnValueStub,
      })

      const items = [memexItemModel, memexItemModel2]

      const error = new Error('User does not have permission to set milestones')
      const bulkUpdateItemsStub = stubRejectedApiResponse(apiBulkUpdateItems, error)

      const {result} = renderHook(useBulkUpdateItemColumnValues, {
        wrapper: createWrapperWithContexts({
          QueryClient: {memexItems: items},
          ToastContainer: createMockToastContainer(),
        }),
      })

      const currentValue = memexItemModel.columns[SystemColumnId.Milestone]
      expect(currentValue).not.toBeUndefined()

      const prevMilestone = item1.memexProjectColumnValues.find(
        c => c.memexProjectColumnId === SystemColumnId.Milestone,
      )?.value
      const prevMilestone2 = item2.memexProjectColumnValues.find(
        c => c.memexProjectColumnId === SystemColumnId.Milestone,
      )?.value
      const newMilestone = getMilestoneByRepository(1, 3)

      const payload = {
        dataType: MemexColumnDataType.Milestone,
        value: newMilestone,
      }

      const itemUpdates = items.map(item => ({
        itemId: item.id,
        updates: [payload],
      }))

      await act(async () => {
        await expect(result.current.bulkUpdateColumnValues(itemUpdates)).rejects.toEqual(error)
      })

      expect(updateColumnValueStub).toHaveBeenCalledTimes(4)
      expect(bulkUpdateItemsStub).toHaveBeenCalledTimes(1)

      expect(mockPostStats).toHaveBeenCalledWith({
        context: 2,
        memexProjectColumnId: 'Milestone',
        name: 'bulk_column_value_update',
        ui: 'shortcut',
      })

      expect(memexItemModel.columns[SystemColumnId.Milestone]).toEqual(currentValue)
      expect(updateColumnValueStub).toHaveBeenNthCalledWith(1, {
        memexProjectColumnId: SystemColumnId.Milestone,
        value: newMilestone,
      })
      expect(updateColumnValueStub).toHaveBeenNthCalledWith(2, {
        memexProjectColumnId: SystemColumnId.Milestone,
        value: newMilestone,
      })
      expect(updateColumnValueStub).toHaveBeenNthCalledWith(3, {
        memexProjectColumnId: SystemColumnId.Milestone,
        value: prevMilestone,
      })
      expect(updateColumnValueStub).toHaveBeenNthCalledWith(4, {
        memexProjectColumnId: SystemColumnId.Milestone,
        value: prevMilestone2,
      })
    })

    it('should not eagerly invalidate the query cache by default', async () => {
      const updateColumnValueStub = stubSetColumnValueForItemColumnType()
      const items = [
        createMemexItemModel(DefaultOpenIssue, {
          setColumnValueForItemColumnType: updateColumnValueStub,
        }),
        createMemexItemModel(DefaultOpenPullRequest, {
          setColumnValueForItemColumnType: updateColumnValueStub,
        }),
      ]

      const bulkUpdateItemsStub = stubResolvedApiResponse(apiBulkUpdateItems, {
        memexProjectItems: items,
        totalUpdatedItems: items.length,
      })

      const {result} = renderHook(useBulkUpdateItemColumnValues, {
        wrapper: createWrapperWithContexts({
          QueryClient: {memexItems: items},
          ToastContainer: createMockToastContainer(),
        }),
      })

      const itemUpdates = items.map(item => ({
        itemId: item.id,
        updates: [
          {
            dataType: MemexColumnDataType.Title,
            value: {title: {raw: 'a new title', html: ''}},
          },
        ],
      }))

      await act(async () => {
        await result.current.bulkUpdateColumnValues(itemUpdates)
      })

      // Verify general success of the bulk update
      expect(bulkUpdateItemsStub).toHaveBeenCalledTimes(1)
      expect(setItemDataStub).toHaveBeenCalledTimes(2)

      // Verify that we did NOT invalidate the query cache
      expect(handleRefreshStub).not.toHaveBeenCalled()
    })

    it('should eagerly invalidate the query cache when the response instructs us to do so', async () => {
      const updateColumnValueStub = stubSetColumnValueForItemColumnType()
      const items = [
        createMemexItemModel(DefaultOpenIssue, {
          setColumnValueForItemColumnType: updateColumnValueStub,
        }),
        createMemexItemModel(DefaultOpenPullRequest, {
          setColumnValueForItemColumnType: updateColumnValueStub,
        }),
      ]

      const bulkUpdateItemsStub = stubResolvedApiResponse(apiBulkUpdateItems, {
        memexProjectItems: items,
        totalUpdatedItems: items.length,
        invalidateQueryCache: true,
      })

      const {result} = renderHook(useBulkUpdateItemColumnValues, {
        wrapper: createWrapperWithContexts({
          QueryClient: {memexItems: items},
          ToastContainer: createMockToastContainer(),
        }),
      })

      const itemUpdates = items.map(item => ({
        itemId: item.id,
        updates: [
          {
            dataType: MemexColumnDataType.Title,
            value: {title: {raw: 'a new title', html: ''}},
          },
        ],
      }))

      await act(async () => {
        await result.current.bulkUpdateColumnValues(itemUpdates)
      })

      // Verify general success of the bulk update
      expect(bulkUpdateItemsStub).toHaveBeenCalledTimes(1)
      expect(setItemDataStub).toHaveBeenCalledTimes(2)

      // Verify that we invalidated the query cache
      expect(handleRefreshStub).toHaveBeenCalledTimes(1)
    })
  })
})

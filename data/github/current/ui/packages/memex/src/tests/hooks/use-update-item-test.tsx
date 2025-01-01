import {act, renderHook} from '@testing-library/react'

import type {UpdateColumnValueAction} from '../../client/api/columns/contracts/domain'
import {SystemColumnId} from '../../client/api/columns/contracts/memex-column'
import {apiUpdateItem} from '../../client/api/memex-items/api-update-item'
import {ItemType} from '../../client/api/memex-items/item-type'
import {useUpdateItem} from '../../client/hooks/use-update-item'
import {columnValueFactory} from '../factories/column-values/column-value-factory'
import {issueFactory} from '../factories/memex-items/issue-factory'
import {stubResolvedApiResponse} from '../mocks/api/memex'
import {createMockToastContainer} from '../mocks/components/toast-container'
import {createMemexItemModel} from '../mocks/models/memex-item-model'
import {createTestQueryClient} from '../test-app-wrapper'
import {createWrapperWithContexts} from '../wrapper-utils'

jest.mock('../../client/api/memex-items/api-update-item')

const findLoadedFieldIdsStub = jest.fn()
jest.mock('../../client/state-providers/columns/use-find-loaded-field-ids', () => {
  return {
    useFindLoadedFieldIdsForCurrentView: () => ({
      findLoadedFieldIds: findLoadedFieldIdsStub,
    }),
  }
})

describe('useUpdateItem', () => {
  describe('updateItem', () => {
    it('requests the currently loaded columns for the item', async () => {
      // Simulate project with only the Title column loaded
      findLoadedFieldIdsStub.mockReturnValueOnce([SystemColumnId.Title])

      const {result} = renderHook(() => useUpdateItem(), {
        wrapper: createWrapperWithContexts({
          QueryClient: {queryClient: createTestQueryClient()},
          ToastContainer: createMockToastContainer(),
        }),
      })

      // Simulate an item in the side panel with Title and Label loaded
      const labelValues = columnValueFactory.labels(['label']).build()
      const titleValue = columnValueFactory.title('title', ItemType.Issue).build()
      const issue = issueFactory.withColumnValues([titleValue, labelValues]).build()
      const item = createMemexItemModel(issue, {setColumnValueForItemColumnType: jest.fn()})

      const updateItemStub = stubResolvedApiResponse(apiUpdateItem, {memexProjectItem: item})
      const updateValue: UpdateColumnValueAction = {
        dataType: 'title',
        value: {title: {raw: 'new title', html: 'new title'}},
      }
      await act(async () => {
        await result.current.updateItem(item, updateValue)
      })

      expect(updateItemStub).toHaveBeenCalledWith({
        memexProjectItemId: item.id,
        fieldIds: [SystemColumnId.Title, SystemColumnId.Labels],
        previousMemexProjectItemId: undefined,
        memexProjectColumnValues: [{memexProjectColumnId: SystemColumnId.Title, value: {title: 'new title'}}],
      })
    })
  })
})

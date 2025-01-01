import {act, renderHook, waitFor} from '@testing-library/react'

import {ItemType} from '../../../client/api/memex-items/item-type'
import {useEnabledFeatures} from '../../../client/hooks/use-enabled-features'
import {useGetSidePanelItemQuery} from '../../../client/hooks/use-get-side-panel-item-query'
import {findMemexItemByIdInQueryClient} from '../../../client/state-providers/memex-items/query-client-api/memex-items'
import {columnValueFactory} from '../../factories/column-values/column-value-factory'
import {issueFactory} from '../../factories/memex-items/issue-factory'
import {stubGetItem} from '../../mocks/api/memex-items'
import {asMockHook} from '../../mocks/stub-utilities'
import {setupEnvironment} from './side-panel-test-helpers'

jest.mock('../../../client/hooks/use-enabled-features')

describe('useGetSidePanelItemQuery', () => {
  beforeEach(() => {
    // Mocking useEnabledFeatures as {} because ColumnsStateProvider code is executed that expects feature flag values.
    asMockHook(useEnabledFeatures).mockReturnValue({})
  })

  it('has no active side pane item by default', () => {
    const {result} = renderHook(useGetSidePanelItemQuery, {wrapper: setupEnvironment().wrapper})

    expect(result.current?.paneItem).toBeUndefined()
  })

  it('item is not loading by default', () => {
    const {result} = renderHook(useGetSidePanelItemQuery, {wrapper: setupEnvironment().wrapper})

    expect(result.current?.isItemLoading).toBe(false)
  })

  it('has an active pane item when hook is passed an item ID', () => {
    const environment = setupEnvironment()
    const item = environment.itemModels[0]
    const {result} = renderHook(() => useGetSidePanelItemQuery(item.id), {wrapper: environment.wrapper})

    expect(result.current?.paneItem?.id).toEqual(item.id)
  })

  it('refetches item data when the pane item is reloaded and updates items cache', async () => {
    const {itemModels, wrapper, queryClient} = setupEnvironment()
    const item = itemModels[0]
    const {result} = renderHook(() => useGetSidePanelItemQuery(item.id), {wrapper})

    // We want to have the response of the `getItem` stub return some new item data, so
    // let's create an item with the same id, but an updated title value.
    const newTitle = 'Updated Title'
    const newItemData = issueFactory.build({
      id: item.id,
      memexProjectColumnValues: [columnValueFactory.title(newTitle, ItemType.Issue).build()],
    })

    const getItemStub = stubGetItem(newItemData)
    expect(getItemStub).not.toHaveBeenCalled()

    act(() => {
      result.current?.reloadPaneItem()
    })

    await waitFor(() => {
      expect(getItemStub).toHaveBeenCalled()
    })

    // After we've called the item stub, we should be able to look up the item in the query cache
    // and verify that the title value has been updated based on the response.
    expect(
      findMemexItemByIdInQueryClient(queryClient, item.id)?.memexProjectColumnValues.find(
        v => v.memexProjectColumnId === 'Title',
      )?.value.title,
    ).toEqual({html: newTitle, raw: newTitle})
  })
})

import {act, renderHook, waitFor} from '@testing-library/react'

import {useViews} from '../../../client/hooks/use-views'
import {
  useFindLoadedFieldIds,
  useFindLoadedFieldIdsForCurrentView,
} from '../../../client/state-providers/columns/use-find-loaded-field-ids'
import {useUpdateLoadedColumns} from '../../../client/state-providers/columns/use-update-loaded-columns'
import {DefaultColumns} from '../../../mocks/data/columns'
import {createMockEnvironment} from '../../create-mock-environment'
import {viewFactory} from '../../factories/views/view-factory'
import {createColumnsStableContext, stubLoadedFieldIdsRef} from '../../mocks/state-providers/columns-stable-context'
import {TestAppContainer} from '../../test-app-wrapper'
import {createWrapperWithColumnsStableContext} from './helpers'

describe('useFindLoadedFieldIds', () => {
  it('calls through to ColumnsStableContext and turns into array', () => {
    const loadedFieldIdsRefStub = stubLoadedFieldIdsRef(new Set([1, 2, 3]))

    const {result} = renderHook(useFindLoadedFieldIds, {
      wrapper: createWrapperWithColumnsStableContext(
        createColumnsStableContext({loadedFieldIdsRef: loadedFieldIdsRefStub}),
      ),
    })

    act(() => {
      const loadedFieldIds = result.current.findLoadedFieldIds()
      expect(loadedFieldIds).toBeDefined()
      expect(loadedFieldIds).toEqual([1, 2, 3])
    })
  })
})

describe('useFindLoadedFieldIdsForCurrentView', () => {
  describe('when memex_table_without_limits is disabled', () => {
    it('loaded field ids are global to the project', async () => {
      const view = viewFactory.table().build()
      const otherView = viewFactory.table().build()
      createMockEnvironment({
        jsonIslandData: {
          'memex-views': [view, otherView],
          'memex-columns-data': DefaultColumns,
        },
      })

      const {result} = renderHook(
        () => ({
          useFindLoadedFieldIdsForCurrentView: useFindLoadedFieldIdsForCurrentView(),
          useViews: useViews(),
          useUpdateLoadedColumns: useUpdateLoadedColumns(),
        }),
        {
          wrapper: TestAppContainer,
        },
      )
      expect(result.current.useViews.currentView?.id).toEqual(view.id)
      act(() => {
        result.current.useUpdateLoadedColumns.updateLoadedColumns(10)
      })
      const loadedFieldIds = result.current.useFindLoadedFieldIdsForCurrentView.findLoadedFieldIds()
      expect(loadedFieldIds).toEqual([10])
      act(() => {
        result.current.useViews.setCurrentViewNumber(otherView.number)
      })
      await waitFor(() => {
        expect(result.current.useViews.currentView?.id).toEqual(otherView.id)
      })
      act(() => {
        result.current.useUpdateLoadedColumns.updateLoadedColumns(20)
      })
      const newLoadedFieldIds = result.current.useFindLoadedFieldIdsForCurrentView.findLoadedFieldIds()
      expect(newLoadedFieldIds).toEqual([10, 20])
    })
  })

  describe('when memex_table_without_limits is enabled', () => {
    it('calls through to ViewsContext and returns field ids for the current view', async () => {
      const view = viewFactory.table().build()
      const otherView = viewFactory.table().build()
      createMockEnvironment({
        jsonIslandData: {
          'memex-enabled-features': ['memex_table_without_limits'],
          'memex-views': [view, otherView],
          'memex-columns-data': DefaultColumns,
        },
      })

      const {result} = renderHook(
        () => ({
          useFindLoadedFieldIdsForCurrentView: useFindLoadedFieldIdsForCurrentView(),
          useViews: useViews(),
        }),
        {
          wrapper: TestAppContainer,
        },
      )
      expect(result.current.useViews.currentView?.id).toEqual(view.id)
      act(() => {
        result.current.useViews.addLoadedFieldIdForCurrentView(10)
      })
      const firstViewLoadedFieldIds = result.current.useFindLoadedFieldIdsForCurrentView.findLoadedFieldIds()
      expect(firstViewLoadedFieldIds).toEqual([10])
      act(() => {
        result.current.useViews.setCurrentViewNumber(otherView.number)
      })
      await waitFor(() => {
        expect(result.current.useViews.currentView?.id).toEqual(otherView.id)
      })
      act(() => {
        result.current.useViews.addLoadedFieldIdForCurrentView(20)
      })
      const otherViewLoadedFieldIds = result.current.useFindLoadedFieldIdsForCurrentView.findLoadedFieldIds()
      expect(otherViewLoadedFieldIds).toEqual([20])
    })
  })
})

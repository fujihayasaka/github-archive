import {act, renderHook} from '@testing-library/react'

import {ViewType} from '../../client/helpers/view-type'
import {usePaginatedVariablesWithFieldIds} from '../../client/hooks/use-paginated-variables-with-field-ids'
import {useViews} from '../../client/hooks/use-views'
import {useVisibleFields} from '../../client/hooks/use-visible-fields'
import {createColumnModel} from '../../client/models/column-model'
import {useNextPlaceholderQuery} from '../../client/state-providers/memex-items/queries/use-next-placeholder-query'
import {customColumnFactory} from '../factories/columns/custom-column-factory'
import {systemColumnFactory} from '../factories/columns/system-column-factory'
import {viewFactory} from '../factories/views/view-factory'
import {asMockHook} from '../mocks/stub-utilities'
import {createTestEnvironment, TestAppContainer} from '../test-app-wrapper'

jest.mock('../../client/state-providers/memex-items/queries/use-next-placeholder-query')

describe('usePaginatedVariablesWithFieldIds', () => {
  const columns = [
    systemColumnFactory.title().build(),
    systemColumnFactory.status({optionNames: ['Todo', 'In progress', 'Done']}).build(),
    systemColumnFactory.assignees().build(),
    customColumnFactory.build(),
  ]
  const visibleColumns = [columns[0], columns[2]]
  const view = viewFactory.table().build({visibleFields: visibleColumns.map(c => c.databaseId)})

  const mockSetUpNextPlaceholderQueries = jest.fn()
  beforeAll(() => {
    asMockHook(useNextPlaceholderQuery).mockReturnValue({
      setUpNextPlaceholderQueries: mockSetUpNextPlaceholderQueries,
    })
  })

  it('returns undefined when no fields are visible', () => {
    createTestEnvironment()
    const {result} = renderHook(() => usePaginatedVariablesWithFieldIds({}), {wrapper: TestAppContainer})
    expect(result.current.fieldIds).toBeUndefined()
  })

  it("returns a sorted list of synthetic ids for the current view's visible fields", () => {
    createTestEnvironment({
      'memex-columns-data': columns,
      'memex-views': [view],
    })

    const {result} = renderHook(() => usePaginatedVariablesWithFieldIds({}), {wrapper: TestAppContainer})
    expect(result.current.fieldIds).toHaveLength(2)
    expect(result.current.fieldIds).toEqual(visibleColumns.map(c => c.id).sort())
  })

  it('seeds placeholder data when fieldIds change', () => {
    mockSetUpNextPlaceholderQueries.mockClear()
    createTestEnvironment({
      'memex-columns-data': columns,
      'memex-views': [view],
    })
    const {result, rerender} = renderHook(
      () => {
        return {
          usePaginatedVariablesWithFieldIds: usePaginatedVariablesWithFieldIds({}),
          useVisibleFields: useVisibleFields(),
        }
      },
      {wrapper: TestAppContainer},
    )
    expect(result.current.usePaginatedVariablesWithFieldIds.fieldIds).toHaveLength(2)
    act(() => {
      result.current.useVisibleFields.showField(view.number, createColumnModel(columns[1]))
    })
    rerender()
    expect(result.current.usePaginatedVariablesWithFieldIds.fieldIds).toHaveLength(3)
    expect(mockSetUpNextPlaceholderQueries).toHaveBeenCalled()
  })

  it('does not attempt to seed placeholder data when fieldIds change because view changed', () => {
    mockSetUpNextPlaceholderQueries.mockClear()
    const otherView = viewFactory.table().build({visibleFields: [columns[1].databaseId]})
    createTestEnvironment({
      'memex-columns-data': columns,
      'memex-views': [view, otherView],
    })
    const {result, rerender} = renderHook(
      () => {
        return {
          usePaginatedVariablesWithFieldIds: usePaginatedVariablesWithFieldIds({}),
          useViews: useViews(),
        }
      },
      {wrapper: TestAppContainer},
    )
    expect(result.current.usePaginatedVariablesWithFieldIds.fieldIds).toHaveLength(2)
    act(() => {
      result.current.useViews.setCurrentViewNumber(otherView.number)
    })
    rerender()
    expect(result.current.usePaginatedVariablesWithFieldIds.fieldIds).toHaveLength(1)
    expect(mockSetUpNextPlaceholderQueries).not.toHaveBeenCalled()
  })

  describe('for roadmap viewTypes', () => {
    it("returns a sorted list of synthetic ids for the view's date and marker fields", () => {
      const startDateField = customColumnFactory.date().build()
      const markerField = columns.find(c => c.dataType === 'assignees')!
      const roadmapView = viewFactory.roadmap().build({
        layoutSettings: {
          roadmap: {dateFields: [startDateField.databaseId, 'none'], markerFields: [markerField?.databaseId]},
        },
      })
      createTestEnvironment({
        'memex-columns-data': columns.concat([startDateField]),
        'memex-views': [roadmapView],
      })

      const {result} = renderHook(() => usePaginatedVariablesWithFieldIds({viewType: ViewType.Roadmap}), {
        wrapper: TestAppContainer,
      })
      expect(result.current.fieldIds).toHaveLength(2)
      expect(result.current.fieldIds).toEqual([startDateField.id, markerField.id].sort())
    })
  })

  it('includes aggregation fields when present', () => {
    const numberFields = [customColumnFactory.number().build(), customColumnFactory.number().build()]
    const aggregatedView = viewFactory.board().build({
      aggregationSettings: {sum: numberFields.map(f => f.databaseId)},
    })
    createTestEnvironment({
      'memex-columns-data': columns.concat(numberFields),
      'memex-views': [aggregatedView],
    })

    const {result} = renderHook(() => usePaginatedVariablesWithFieldIds({viewType: ViewType.Board}), {
      wrapper: TestAppContainer,
    })
    expect(result.current.fieldIds).toHaveLength(2)
    expect(result.current.fieldIds).toEqual(numberFields.map(f => f.id).sort())
  })

  it('properly memoizes return object', () => {
    createTestEnvironment({
      'memex-columns-data': columns,
      'memex-views': [view],
    })
    const variablesWithoutFieldIds = {}
    const {result, rerender} = renderHook(() => usePaginatedVariablesWithFieldIds(variablesWithoutFieldIds), {
      wrapper: TestAppContainer,
    })
    const initialReturnObject = result.current
    rerender(variablesWithoutFieldIds)
    const secondReturnObject = result.current

    expect(initialReturnObject).toBe(secondReturnObject)
  })
})

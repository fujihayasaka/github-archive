import {renderHook} from '@testing-library/react'

import type {MemexChartConfiguration} from '../../../client/api/charts/contracts/api'
import {createMemexItemModel, type MemexItemModel} from '../../../client/models/memex-item-model'
import {useChartSeriesCardCharts} from '../../../client/state-providers/charts/use-chart-series-card-charts'
import {
  assigneesColumn,
  customNumberColumn,
  DefaultColumns,
  labelsColumn,
  stageColumn,
  statusColumn,
} from '../../../mocks/data/columns'
import {
  DefaultClosedPullRequest,
  DefaultCopyIssue,
  DefaultOpenIssue,
  IssueWithAFixedAssignee,
  OverflowingClosedIssue,
} from '../../../mocks/memex-items'
import {createTestQueryClient} from '../../test-app-wrapper'
import {createWrapperWithContexts} from '../../wrapper-utils'

const allItems = [
  createMemexItemModel(DefaultOpenIssue),
  createMemexItemModel(IssueWithAFixedAssignee),
  createMemexItemModel(DefaultCopyIssue),
  createMemexItemModel(OverflowingClosedIssue),
  createMemexItemModel(DefaultOpenIssue),
  createMemexItemModel(DefaultClosedPullRequest),
]
let chartConfiguration: MemexChartConfiguration
let filteredItems: Array<MemexItemModel>

jest.mock('../../../client/state-providers/memex-items/use-memex-items', () => ({
  __esModule: true,
  useMemexItems: jest.fn(() => {
    return {
      items: allItems,
    }
  }),
}))

jest.mock('../../../client/state-providers/columns/use-find-column-by-database-id', () => ({
  __esModule: true,
  useFindColumnByDatabaseId: jest.fn(() => {
    return {
      findColumnByDatabaseId: (databaseId: number) => DefaultColumns.find(c => c.databaseId === databaseId),
    }
  }),
}))

describe('useChartSeriesCardCharts', () => {
  describe('with count aggregation', () => {
    beforeEach(() => {
      chartConfiguration = {
        filter: '',
        type: 'column',
        xAxis: {dataSource: {column: statusColumn.databaseId}},
        yAxis: {aggregate: {operation: 'count', columns: [assigneesColumn.databaseId]}},
      }

      filteredItems = [allItems[0], allItems[1], allItems[2]]
    })

    it('should build series axis with two elements if there is no groupBy in configuration', () => {
      const queryClient = createTestQueryClient()
      const {result} = renderHook(() => useChartSeriesCardCharts(chartConfiguration, filteredItems), {
        wrapper: createWrapperWithContexts({
          QueryClient: {queryClient},
        }),
      })

      expect(result.current.axis).toEqual({
        xAxis: {dataType: 'nvarchar', name: 'Status'},
        yAxis: {dataType: 'int', name: 'Count'},
      })
    })

    it('should build empty series axis if there are no items', () => {
      const {result} = renderHook(() => useChartSeriesCardCharts(chartConfiguration, []), {
        wrapper: createWrapperWithContexts({
          QueryClient: {queryClient: createTestQueryClient()},
        }),
      })

      expect(result.current.series).toEqual([])
    })

    it('should build series from all items if items are not filtered', () => {
      const {result} = renderHook(() => useChartSeriesCardCharts(chartConfiguration, null), {
        wrapper: createWrapperWithContexts({
          QueryClient: {queryClient: createTestQueryClient()},
        }),
      })

      expect(result.current.series).toEqual([{name: 'Sum of Estimate', data: [2, 2, 2]}])
      expect(result.current.xCoordinates).toEqual(['Backlog', 'Done', 'No Status'])
    })

    it('should return series for filtered items', () => {
      const {result} = renderHook(() => useChartSeriesCardCharts(chartConfiguration, filteredItems), {
        wrapper: createWrapperWithContexts({
          QueryClient: {queryClient: createTestQueryClient()},
        }),
      })

      expect(result.current.series).toEqual([{name: 'Sum of Estimate', data: [1, 1, 1]}])
      expect(result.current.xCoordinates).toEqual(['Backlog', 'Done', 'No Status'])
    })

    it('should return series for filtered items with groupBy', () => {
      chartConfiguration.xAxis.groupBy = {column: labelsColumn.databaseId}

      const {result} = renderHook(() => useChartSeriesCardCharts(chartConfiguration, filteredItems), {
        wrapper: createWrapperWithContexts({
          QueryClient: {queryClient: createTestQueryClient()},
        }),
      })

      expect(result.current.series).toEqual([
        {name: 'enhancement ✨', data: [1, 1, 0]},
        {name: 'tech debt', data: [0, 1, 0]},
        {name: 'No Labels', data: [0, 0, 1]},
      ])
      expect(result.current.xCoordinates).toEqual(['Backlog', 'Done', 'No Status'])
    })
  })

  describe('with sum operation', () => {
    beforeEach(() => {
      chartConfiguration = {
        filter: '',
        type: 'column',
        xAxis: {dataSource: {column: statusColumn.databaseId}},
        yAxis: {aggregate: {operation: 'sum', columns: [customNumberColumn.databaseId]}},
      }

      filteredItems = [allItems[0], allItems[2], allItems[5]]
    })

    it('should build series from all items if items are not filtered', () => {
      const {result} = renderHook(() => useChartSeriesCardCharts(chartConfiguration, null), {
        wrapper: createWrapperWithContexts({
          QueryClient: {queryClient: createTestQueryClient()},
        }),
      })

      expect(result.current.series).toEqual([{name: 'Sum of Estimate', data: [2, 20, 0]}])
      expect(result.current.xCoordinates).toEqual(['Backlog', 'Done', 'No Status'])
    })

    it('should build series axis with y-axis label', () => {
      const {result} = renderHook(() => useChartSeriesCardCharts(chartConfiguration, filteredItems), {
        wrapper: createWrapperWithContexts({
          QueryClient: {queryClient: createTestQueryClient()},
        }),
      })

      expect(result.current.axis).toEqual({
        xAxis: {dataType: 'nvarchar', name: 'Status'},
        yAxis: {dataType: 'int', name: 'Sum of Estimate'},
      })
    })

    it('should return series for filtered items with groupBy', () => {
      chartConfiguration.xAxis.groupBy = {column: stageColumn.databaseId}

      const {result} = renderHook(() => useChartSeriesCardCharts(chartConfiguration, filteredItems), {
        wrapper: createWrapperWithContexts({
          QueryClient: {queryClient: createTestQueryClient()},
        }),
      })

      expect(result.current.series).toEqual([
        {name: 'No Stage', data: [1, 10]},
        {name: 'Closed', data: [0, 10]},
      ])
      expect(result.current.xCoordinates).toEqual(['Backlog', 'Done'])
    })
  })

  describe('with avg operation', () => {
    beforeEach(() => {
      chartConfiguration = {
        filter: '',
        type: 'column',
        xAxis: {dataSource: {column: statusColumn.databaseId}},
        yAxis: {aggregate: {operation: 'avg', columns: [customNumberColumn.databaseId]}},
      }

      filteredItems = [allItems[0], allItems[2], allItems[5]]
    })

    it('should build series from all items if items are not filtered', () => {
      const {result} = renderHook(() => useChartSeriesCardCharts(chartConfiguration, null), {
        wrapper: createWrapperWithContexts({
          QueryClient: {queryClient: createTestQueryClient()},
        }),
      })

      expect(result.current.series).toEqual([{name: 'Sum of Estimate', data: [1, 10, 0]}])
      expect(result.current.xCoordinates).toEqual(['Backlog', 'Done', 'No Status'])
    })

    it('should build series axis with y-axis label', () => {
      const {result} = renderHook(() => useChartSeriesCardCharts(chartConfiguration, filteredItems), {
        wrapper: createWrapperWithContexts({
          QueryClient: {queryClient: createTestQueryClient()},
        }),
      })

      expect(result.current.axis).toEqual({
        xAxis: {dataType: 'nvarchar', name: 'Status'},
        yAxis: {dataType: 'int', name: 'Average of Estimate'},
      })
    })

    it('should return series for filtered items', () => {
      const {result} = renderHook(() => useChartSeriesCardCharts(chartConfiguration, filteredItems), {
        wrapper: createWrapperWithContexts({
          QueryClient: {queryClient: createTestQueryClient()},
        }),
      })

      expect(result.current.series).toEqual([{name: 'Sum of Estimate', data: [1, 10]}])
      expect(result.current.xCoordinates).toEqual(['Backlog', 'Done'])
    })

    it('should return series for filtered items with groupBy', () => {
      chartConfiguration.xAxis.groupBy = {column: stageColumn.databaseId}

      const {result} = renderHook(() => useChartSeriesCardCharts(chartConfiguration, filteredItems), {
        wrapper: createWrapperWithContexts({
          QueryClient: {queryClient: createTestQueryClient()},
        }),
      })

      expect(result.current.series).toEqual([
        {name: 'No Stage', data: [1, 10]},
        {name: 'Closed', data: [0, 10]},
      ])
      expect(result.current.xCoordinates).toEqual(['Backlog', 'Done'])
    })
  })

  describe('with min operation', () => {
    beforeEach(() => {
      chartConfiguration = {
        filter: '',
        type: 'column',
        xAxis: {dataSource: {column: statusColumn.databaseId}},
        yAxis: {aggregate: {operation: 'min', columns: [customNumberColumn.databaseId]}},
      }

      filteredItems = [allItems[0], allItems[3], allItems[4]]
    })

    it('should build series from all items if items are not filtered', () => {
      const {result} = renderHook(() => useChartSeriesCardCharts(chartConfiguration, null), {
        wrapper: createWrapperWithContexts({
          QueryClient: {queryClient: createTestQueryClient()},
        }),
      })

      expect(result.current.series).toEqual([{name: 'Sum of Estimate', data: [1, 10, 0]}])
      expect(result.current.xCoordinates).toEqual(['Backlog', 'Done', 'No Status'])
    })

    it('should build series axis with y-axis label', () => {
      const {result} = renderHook(() => useChartSeriesCardCharts(chartConfiguration, filteredItems), {
        wrapper: createWrapperWithContexts({
          QueryClient: {queryClient: createTestQueryClient()},
        }),
      })

      expect(result.current.axis).toEqual({
        xAxis: {dataType: 'nvarchar', name: 'Status'},
        yAxis: {dataType: 'int', name: 'Minimum of Estimate'},
      })
    })

    it('should return series for filtered items', () => {
      const {result} = renderHook(() => useChartSeriesCardCharts(chartConfiguration, filteredItems), {
        wrapper: createWrapperWithContexts({
          QueryClient: {queryClient: createTestQueryClient()},
        }),
      })

      expect(result.current.series).toEqual([{name: 'Sum of Estimate', data: [1, 0]}])
      expect(result.current.xCoordinates).toEqual(['Backlog', 'No Status'])
    })

    it('should return series for filtered items with groupBy', () => {
      chartConfiguration.xAxis.groupBy = {column: stageColumn.databaseId}

      const {result} = renderHook(() => useChartSeriesCardCharts(chartConfiguration, filteredItems), {
        wrapper: createWrapperWithContexts({
          QueryClient: {queryClient: createTestQueryClient()},
        }),
      })
      expect(result.current.series).toEqual([{name: 'No Stage', data: [1, 0]}])
      expect(result.current.xCoordinates).toEqual(['Backlog', 'No Status'])
    })
  })

  describe('with max operation', () => {
    beforeEach(() => {
      chartConfiguration = {
        filter: '',
        type: 'column',
        xAxis: {dataSource: {column: statusColumn.databaseId}},
        yAxis: {aggregate: {operation: 'max', columns: [customNumberColumn.databaseId]}},
      }

      filteredItems = [allItems[0], allItems[3], allItems[5]]
    })

    it('should build series from all items if items are not filtered', () => {
      const {result} = renderHook(() => useChartSeriesCardCharts(chartConfiguration, null), {
        wrapper: createWrapperWithContexts({
          QueryClient: {queryClient: createTestQueryClient()},
        }),
      })

      expect(result.current.series).toEqual([{name: 'Sum of Estimate', data: [1, 10, 0]}])
      expect(result.current.xCoordinates).toEqual(['Backlog', 'Done', 'No Status'])
    })

    it('should build series axis with y-axis label', () => {
      const {result} = renderHook(() => useChartSeriesCardCharts(chartConfiguration, filteredItems), {
        wrapper: createWrapperWithContexts({
          QueryClient: {queryClient: createTestQueryClient()},
        }),
      })

      expect(result.current.axis).toEqual({
        xAxis: {dataType: 'nvarchar', name: 'Status'},
        yAxis: {dataType: 'int', name: 'Maximum of Estimate'},
      })
    })

    it('should return series for filtered items', () => {
      const {result} = renderHook(() => useChartSeriesCardCharts(chartConfiguration, filteredItems), {
        wrapper: createWrapperWithContexts({
          QueryClient: {queryClient: createTestQueryClient()},
        }),
      })

      expect(result.current.series).toEqual([{name: 'Sum of Estimate', data: [1, 10, 0]}])
      expect(result.current.xCoordinates).toEqual(['Backlog', 'Done', 'No Status'])
    })

    it('should return series for filtered items with groupBy', () => {
      chartConfiguration.xAxis.groupBy = {column: stageColumn.databaseId}

      const {result} = renderHook(() => useChartSeriesCardCharts(chartConfiguration, filteredItems), {
        wrapper: createWrapperWithContexts({
          QueryClient: {queryClient: createTestQueryClient()},
        }),
      })

      expect(result.current.series).toEqual([
        {name: 'No Stage', data: [1, 0, 0]},
        {name: 'Closed', data: [0, 10, 0]},
      ])
      expect(result.current.xCoordinates).toEqual(['Backlog', 'Done', 'No Status'])
    })
  })
})

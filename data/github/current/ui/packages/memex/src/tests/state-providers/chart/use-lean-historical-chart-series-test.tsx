import {renderHook} from '@testing-library/react'
import {subDays} from 'date-fns'

import type {MemexChartConfiguration} from '../../../client/api/charts/contracts/api'
import type {SystemColumnId} from '../../../client/api/columns/contracts/memex-column'
import {createMemexItemModel} from '../../../client/models/memex-item-model'
import {
  LeanHistoricalStateType,
  useLeanHistoricalChartSeriesChartCard,
} from '../../../client/state-providers/charts/use-lean-historical-chart-series'
import {customNumberColumn} from '../../../mocks/data/columns'
import {generateLeanHistoricalInsightsData} from '../../../mocks/data/generated'
import {DefaultColumns} from '../../../mocks/mock-data'

// use a fixed date to avoid test flakiness
const now = new Date('2023-08-01T00:00:00.000Z')
const allItems = generateLeanHistoricalInsightsData({columns: DefaultColumns}, now).map(item =>
  createMemexItemModel(item),
)

jest.useFakeTimers().setSystemTime(now)

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

function getDatabaseIdByColumnId(columnId: number | SystemColumnId) {
  return DefaultColumns.filter(column => column.id === columnId).map(column => column.databaseId)
}

const minDaysPerMonth = 28
const generatedRowsPerDay = 3
const defaultConfig: MemexChartConfiguration = {
  filter: '',
  type: 'stacked-area',
  xAxis: {
    dataSource: {
      column: 'time',
    },
    groupBy: {
      column: 12,
    },
  },
  yAxis: {
    aggregate: {
      operation: 'count',
    },
  },
  time: {
    period: '2W',
  },
}

describe('useLeanHistoricalChartSeriesChartCard', () => {
  describe('with count aggregation', () => {
    it('check index value of state type', () => {
      const {result} = renderHook(() =>
        useLeanHistoricalChartSeriesChartCard({
          configuration: defaultConfig,
          filteredItems: allItems,
        }),
      )

      const series = result.current.series

      expect(series.find(s => s.name === LeanHistoricalStateType.NOT_PLANNED)?.index).toBe(3)
      expect(series.find(s => s.name === LeanHistoricalStateType.CLOSED)?.index).toBe(2)
      expect(series.find(s => s.name === LeanHistoricalStateType.COMPLETED)?.index).toBe(1)
      expect(series.find(s => s.name === LeanHistoricalStateType.OPEN)?.index).toBe(0)
    })

    it('should build empty series when theres no item data available', () => {
      const {result} = renderHook(() =>
        useLeanHistoricalChartSeriesChartCard({
          configuration: defaultConfig,
          filteredItems: [],
          startDate: subDays(now, 14).toISOString(),
          endDate: now.toISOString(),
        }),
      )
      expect(result.current.series).toEqual([])
    })

    it('should build the expected number of series data for a 2W period', () => {
      const {result} = renderHook(() =>
        useLeanHistoricalChartSeriesChartCard({
          configuration: defaultConfig,
          filteredItems: allItems,
        }),
      )
      const series = result.current.series.flat()
      const count = series.reduce((acc, cur) => {
        return (acc += cur.data.length)
      }, 0)

      expect(count).toBeGreaterThanOrEqual(14 * generatedRowsPerDay)
    })

    it('should build the expected number of series data for a 1M period', () => {
      const {result} = renderHook(() =>
        useLeanHistoricalChartSeriesChartCard({
          configuration: {
            ...defaultConfig,
            time: {
              period: '1M',
            },
          },
          filteredItems: allItems,
        }),
      )
      const series = result.current.series.flat()
      const count = series.reduce((acc, cur) => {
        return (acc += cur.data.length)
      }, 0)

      expect(count).toBeGreaterThanOrEqual(minDaysPerMonth * generatedRowsPerDay)
    })

    it('should build the expected number of series data for a 3M period', () => {
      const {result} = renderHook(() =>
        useLeanHistoricalChartSeriesChartCard({
          configuration: {
            ...defaultConfig,
            time: {
              period: '3M',
            },
          },
          filteredItems: allItems,
        }),
      )
      const series = result.current.series.flat()
      const count = series.reduce((acc, cur) => {
        return (acc += cur.data.length)
      }, 0)

      expect(count).toBeGreaterThanOrEqual(minDaysPerMonth * 3 * generatedRowsPerDay)
    })

    it('should build the expected number of series data for a MAX period', () => {
      const {result} = renderHook(() =>
        useLeanHistoricalChartSeriesChartCard({
          configuration: {
            ...defaultConfig,
            time: {
              period: 'max',
            },
          },
          filteredItems: allItems,
        }),
      )
      const series = result.current.series.flat()
      const count = series.reduce((acc, cur) => {
        return (acc += cur.data.length)
      }, 0)

      expect(count).toBeGreaterThanOrEqual(minDaysPerMonth * 6 * generatedRowsPerDay)
    })

    it('should build the expected number of series data for a custom range', () => {
      const {result} = renderHook(() =>
        useLeanHistoricalChartSeriesChartCard({
          configuration: {
            ...defaultConfig,
            time: {
              period: 'custom',
            },
          },
          filteredItems: null,
          startDate: subDays(now, 7).toISOString(),
          endDate: now.toISOString(),
        }),
      )
      const series = result.current.series.flat()
      const count = series.reduce((acc, cur) => {
        return (acc += cur.data.length)
      }, 0)

      expect(count).toBeGreaterThanOrEqual(7 * generatedRowsPerDay)
    })

    it('should build the expected series data when using "Count of items" Y-axis aggregation', () => {
      const {result} = renderHook(() =>
        useLeanHistoricalChartSeriesChartCard({
          configuration: defaultConfig,
          filteredItems: allItems,
        }),
      )

      const series = result.current.series

      expect(series.find(s => s.name === LeanHistoricalStateType.NOT_PLANNED)?.data.pop()).toBeGreaterThan(0)
      expect(series.find(s => s.name === LeanHistoricalStateType.CLOSED)?.data.pop()).toBeGreaterThan(0)
      expect(series.find(s => s.name === LeanHistoricalStateType.COMPLETED)?.data.pop()).toBeGreaterThan(0)
      expect(series.find(s => s.name === LeanHistoricalStateType.OPEN)?.data.pop()).toBe(0)
    })

    it('should build the expected series data when using "Sum of a field" Y-axis aggregation', () => {
      const {result} = renderHook(() =>
        useLeanHistoricalChartSeriesChartCard({
          configuration: {
            ...defaultConfig,
            yAxis: {
              aggregate: {
                columns: getDatabaseIdByColumnId(customNumberColumn.id),
                operation: 'sum',
              },
            },
          },
          filteredItems: allItems,
        }),
      )

      const series = result.current.series

      expect(series.find(s => s.name === LeanHistoricalStateType.NOT_PLANNED)?.data.pop()).toBeGreaterThan(100000)
      expect(series.find(s => s.name === LeanHistoricalStateType.CLOSED)?.data.pop()).toBeGreaterThan(100000)
      expect(series.find(s => s.name === LeanHistoricalStateType.COMPLETED)?.data.pop()).toBeGreaterThan(100000)
      expect(series.find(s => s.name === LeanHistoricalStateType.OPEN)?.data.pop()).toBe(0)
    })

    it('should build the expected series data when using "Average of a field" Y-axis aggregation', () => {
      const {result} = renderHook(() =>
        useLeanHistoricalChartSeriesChartCard({
          configuration: {
            ...defaultConfig,
            yAxis: {
              aggregate: {
                columns: getDatabaseIdByColumnId(customNumberColumn.id),
                operation: 'avg',
              },
            },
          },
          filteredItems: allItems,
        }),
      )

      const series = result.current.series

      expect(series.find(s => s.name === LeanHistoricalStateType.NOT_PLANNED)?.data.pop()).toBeGreaterThan(10000)
      expect(series.find(s => s.name === LeanHistoricalStateType.CLOSED)?.data.pop()).toBeGreaterThan(10000)
      expect(series.find(s => s.name === LeanHistoricalStateType.COMPLETED)?.data.pop()).toBeGreaterThan(10000)
      expect(series.find(s => s.name === LeanHistoricalStateType.OPEN)?.data.pop()).toBe(0)
    })

    it('should build the expected series data when using "Minimum of a field" Y-axis aggregation', () => {
      const {result} = renderHook(() =>
        useLeanHistoricalChartSeriesChartCard({
          configuration: {
            ...defaultConfig,
            yAxis: {
              aggregate: {
                columns: getDatabaseIdByColumnId(customNumberColumn.id),
                operation: 'min',
              },
            },
          },
          filteredItems: allItems,
        }),
      )

      const series = result.current.series

      expect(series.find(s => s.name === LeanHistoricalStateType.NOT_PLANNED)?.data.pop()).toBeGreaterThan(0)
      expect(series.find(s => s.name === LeanHistoricalStateType.CLOSED)?.data.pop()).toBeGreaterThan(0)
      expect(series.find(s => s.name === LeanHistoricalStateType.COMPLETED)?.data.pop()).toBeGreaterThan(0)
      expect(series.find(s => s.name === LeanHistoricalStateType.OPEN)?.data.pop()).toBe(0)
    })

    it('should build the expected series data when using "Maximum of a field" Y-axis aggregation', () => {
      const {result} = renderHook(() =>
        useLeanHistoricalChartSeriesChartCard({
          configuration: {
            ...defaultConfig,
            yAxis: {
              aggregate: {
                columns: getDatabaseIdByColumnId(customNumberColumn.id),
                operation: 'max',
              },
            },
          },
          filteredItems: allItems,
        }),
      )

      const series = result.current.series

      expect(series.find(s => s.name === LeanHistoricalStateType.NOT_PLANNED)?.data.pop()).toBeGreaterThan(10000)
      expect(series.find(s => s.name === LeanHistoricalStateType.CLOSED)?.data.pop()).toBeGreaterThan(10000)
      expect(series.find(s => s.name === LeanHistoricalStateType.COMPLETED)?.data.pop()).toBeGreaterThan(10000)
      expect(series.find(s => s.name === LeanHistoricalStateType.OPEN)?.data.pop()).toBe(0)
    })
  })
})

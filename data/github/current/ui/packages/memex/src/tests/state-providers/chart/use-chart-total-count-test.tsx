import {renderHook, waitFor} from '@testing-library/react'

import type {MemexChartConfiguration} from '../../../client/api/charts/contracts/api'
import type {GetChartResponse} from '../../../client/api/insights/contracts'
import {useChartTotalCount} from '../../../client/queries/use-chart-total-count'
import {useChartSeries} from '../../../client/state-providers/charts/use-chart-series'
import {useHistoricalChartSeries} from '../../../client/state-providers/charts/use-historical-chart-series'
import {statusColumn} from '../../../mocks/data/columns'
import {stubGetChartRequest} from '../../mocks/api/memex-items'
import {stubAllColumnsRef} from '../../mocks/state-providers/columns-context'
import {createColumnsStableContext} from '../../mocks/state-providers/columns-stable-context'
import {createTestQueryClient} from '../../test-app-wrapper'
import {createWrapperWithContexts} from '../../wrapper-utils'

const defaultHistoricalConfig: MemexChartConfiguration = {
  filter: 'has:assignee -status:"🎉 Done"',
  type: 'stacked-area',
  xAxis: {
    dataSource: {
      column: 'time',
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

const buildGetChartHistoricalResponse = () => {
  return {
    xAxis: {
      values: ['2024-12-04', '2024-12-31', '2025-01-06', '2025-01-07'],
    },
    dataSeries: [
      {
        name: 'Open',
        data: [8, 4, 2, 1],
      },
      {
        name: 'Completed',
        data: [3, 1, 2, 4],
      },
    ],
    totalCount: 8,
  }
}

const defaultChartSeriesConfig = (filter: string = ''): MemexChartConfiguration => ({
  filter,
  type: 'column',
  xAxis: {
    dataSource: {
      column: statusColumn.databaseId,
    },
  },
  yAxis: {
    aggregate: {
      operation: 'count',
      columns: [],
    },
  },
})

const buildGetChartSeriesResponse = () => {
  return {
    xAxis: {
      values: ['Todo', 'In Progress', 'Done', '_noValue'],
    },
    dataSeries: [
      {
        name: '',
        data: [8, 4, 25, 13],
      },
    ],
    totalCount: 50,
  }
}

const mockGetChartReponse = (response: GetChartResponse) => {
  return stubGetChartRequest(response)
}

describe('useChartTotalFilterCount', () => {
  it('returns undefined total count if cache is not primed', () => {
    const queryClient = createTestQueryClient()
    const {result} = renderHook(() => useChartTotalCount(defaultChartSeriesConfig('is:issue')), {
      wrapper: createWrapperWithContexts({
        QueryClient: {queryClient},
      }),
    })

    expect(result.current.filterCount).toBeUndefined()
  })

  it('returns undefined when filter is falsy', async () => {
    const allColumnsStub = stubAllColumnsRef([statusColumn])
    const mockRequest = mockGetChartReponse(buildGetChartSeriesResponse())
    const queryClient = createTestQueryClient()

    const {result: chartSeriesResult} = renderHook(() => useChartSeries(defaultChartSeriesConfig()), {
      wrapper: createWrapperWithContexts({
        QueryClient: {queryClient},
        ColumnsStable: createColumnsStableContext({allColumnsRef: allColumnsStub}),
      }),
    })

    expect(chartSeriesResult.current.isLoading).toBe(true)
    expect(chartSeriesResult.current.series).toHaveLength(0)
    expect(chartSeriesResult.current.xCoordinates).toHaveLength(0)

    await waitFor(() => {
      expect(mockRequest).toHaveBeenCalled()
    })

    expect(chartSeriesResult.current.isLoading).toBe(false)

    const {result} = renderHook(() => useChartTotalCount(defaultChartSeriesConfig()), {
      wrapper: createWrapperWithContexts({
        QueryClient: {queryClient},
      }),
    })

    expect(result.current.filterCount).toBeUndefined()
  })

  it('should return total filter count from chart series data in cache', async () => {
    const allColumnsStub = stubAllColumnsRef([statusColumn])
    const mockRequest = mockGetChartReponse(buildGetChartSeriesResponse())
    const queryClient = createTestQueryClient()

    const filter = 'is:issue'
    const {result: chartSeriesResult} = renderHook(() => useChartSeries(defaultChartSeriesConfig(filter)), {
      wrapper: createWrapperWithContexts({
        QueryClient: {queryClient},
        ColumnsStable: createColumnsStableContext({allColumnsRef: allColumnsStub}),
      }),
    })

    expect(chartSeriesResult.current.isLoading).toBe(true)
    expect(chartSeriesResult.current.series).toHaveLength(0)
    expect(chartSeriesResult.current.xCoordinates).toHaveLength(0)

    await waitFor(() => {
      expect(mockRequest).toHaveBeenCalled()
    })

    expect(chartSeriesResult.current.isLoading).toBe(false)

    const {result} = renderHook(() => useChartTotalCount(defaultChartSeriesConfig(filter)), {
      wrapper: createWrapperWithContexts({
        QueryClient: {queryClient},
      }),
    })

    expect(result.current.filterCount).toBe(50)
  })

  it('should return total filter count from historical chart data in cache', async () => {
    const allColumnsStub = stubAllColumnsRef([statusColumn])
    const mockRequest = mockGetChartReponse(buildGetChartHistoricalResponse())
    const queryClient = createTestQueryClient()

    const {result: chartSeriesResult} = renderHook(
      () => useHistoricalChartSeries({configuration: defaultHistoricalConfig}),
      {
        wrapper: createWrapperWithContexts({
          QueryClient: {queryClient},
          ColumnsStable: createColumnsStableContext({allColumnsRef: allColumnsStub}),
        }),
      },
    )

    expect(chartSeriesResult.current.isLoading).toBe(true)
    expect(chartSeriesResult.current.series).toHaveLength(0)
    expect(chartSeriesResult.current.xCoordinates).toHaveLength(0)

    await waitFor(() => {
      expect(mockRequest).toHaveBeenCalled()
    })

    expect(chartSeriesResult.current.isLoading).toBe(false)

    const {result} = renderHook(() => useChartTotalCount(defaultHistoricalConfig), {
      wrapper: createWrapperWithContexts({
        QueryClient: {queryClient},
      }),
    })

    expect(result.current.filterCount).toBe(8)
  })
})

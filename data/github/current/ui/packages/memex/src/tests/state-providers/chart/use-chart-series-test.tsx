import {renderHook, waitFor} from '@testing-library/react'

import type {MemexChartConfiguration, MemexChartOperation} from '../../../client/api/charts/contracts/api'
import type {GetChartResponse} from '../../../client/api/insights/contracts'
import {useChartSeries} from '../../../client/state-providers/charts/use-chart-series'
import {assigneesColumn, effortColumn, labelsColumn, statusColumn} from '../../../mocks/data/columns'
import {stubGetChartRequest} from '../../mocks/api/memex-items'
import {stubAllColumnsRef} from '../../mocks/state-providers/columns-context'
import {createColumnsStableContext} from '../../mocks/state-providers/columns-stable-context'
import {createTestQueryClient} from '../../test-app-wrapper'
import {createWrapperWithContexts} from '../../wrapper-utils'

const defaultConfig = (
  xAxisColumnId: number = statusColumn.databaseId,
  yAxisColumnId?: number,
  yAxisAggregateOperation?: MemexChartOperation,
): MemexChartConfiguration => ({
  filter: '',
  type: 'column',
  xAxis: {
    dataSource: {
      column: xAxisColumnId,
    },
  },
  yAxis: {
    aggregate: {
      operation: yAxisAggregateOperation ?? 'count',
      columns: yAxisColumnId ? [yAxisColumnId] : [],
    },
  },
})

const groupByConfig = (
  xAxisColumnId: number = statusColumn.databaseId,
  xAxisGroupByColumnId: number = statusColumn.databaseId,
): MemexChartConfiguration => ({
  filter: '',
  type: 'column',
  xAxis: {
    dataSource: {
      column: xAxisColumnId,
    },
    groupBy: {
      column: xAxisGroupByColumnId,
    },
  },
  yAxis: {
    aggregate: {
      operation: 'count',
    },
  },
})

const buildGetChartResponse = () => {
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

const buildGetGroupChartResponse = () => {
  return {
    xAxis: {
      values: ['Todo', 'In Progress', 'Done', '_noValue'],
    },
    dataSeries: [
      {
        name: 'Closed milestone',
        data: [6, 1, 10, 3],
      },
      {
        name: 'Open milestone',
        data: [1, 1, 12, 4],
      },
      {
        name: '_noValue',
        data: [1, 2, 3, 6],
      },
    ],
    totalCount: 50,
  }
}

const mockGetChartReponse = (response: GetChartResponse) => {
  return stubGetChartRequest(response)
}

describe('useChartSeries', () => {
  it('makes a request to the charts API', async () => {
    const allColumnsStub = stubAllColumnsRef([statusColumn])
    const mockRequest = mockGetChartReponse(buildGetChartResponse())
    const queryClient = createTestQueryClient()

    const {result} = renderHook(() => useChartSeries(defaultConfig()), {
      wrapper: createWrapperWithContexts({
        QueryClient: {queryClient},
        ColumnsStable: createColumnsStableContext({allColumnsRef: allColumnsStub}),
      }),
    })

    expect(result.current.isLoading).toBe(true)
    expect(result.current.series).toHaveLength(0)
    expect(result.current.xCoordinates).toHaveLength(0)

    await waitFor(() => {
      expect(mockRequest).toHaveBeenCalled()
    })

    expect(result.current.isLoading).toBe(false)
    expect(result.current.series).toHaveLength(1)
    expect(result.current.xCoordinates).toHaveLength(4)
    expect(result.current.series[0].name).toBe('Count of Items')
    expect(result.current.series[0].data).toEqual([8, 4, 25, 13])
    expect(result.current.xCoordinates).toEqual(['Todo', 'In Progress', 'Done', 'No Status'])
  })

  it('makes a request to the charts API with groupBy configuration', async () => {
    const allColumnsStub = stubAllColumnsRef([assigneesColumn, labelsColumn])
    const mockRequest = mockGetChartReponse(buildGetGroupChartResponse())
    const queryClient = createTestQueryClient()

    const {result} = renderHook(
      () => useChartSeries(groupByConfig(assigneesColumn.databaseId, labelsColumn.databaseId)),
      {
        wrapper: createWrapperWithContexts({
          QueryClient: {queryClient},
          ColumnsStable: createColumnsStableContext({allColumnsRef: allColumnsStub}),
        }),
      },
    )

    expect(result.current.isLoading).toBe(true)
    expect(result.current.series).toHaveLength(0)
    expect(result.current.xCoordinates).toHaveLength(0)

    await waitFor(() => {
      expect(mockRequest).toHaveBeenCalled()
    })

    expect(result.current.isLoading).toBe(false)
    expect(result.current.series).toHaveLength(3)
    expect(result.current.xCoordinates).toHaveLength(4)
    expect(result.current.series[0].name).toBe('Closed milestone')
    expect(result.current.series[0].data).toEqual([6, 1, 10, 3])
    expect(result.current.series[1].name).toBe('Open milestone')
    expect(result.current.series[1].data).toEqual([1, 1, 12, 4])
    expect(result.current.series[2].name).toBe('No Labels')
    expect(result.current.series[2].data).toEqual([1, 2, 3, 6])
    expect(result.current.xCoordinates).toEqual(['Todo', 'In Progress', 'Done', 'No Assignees'])
  })

  it.each([
    {operation: 'count', expected: 'Count of Items'},
    {operation: 'sum', expected: `Sum of ${effortColumn.name}`},
    {operation: 'avg', expected: `Average of ${effortColumn.name}`},
    {operation: 'min', expected: `Minimum of ${effortColumn.name}`},
    {operation: 'max', expected: `Maximum of ${effortColumn.name}`},
  ])(
    'makes a request to the charts API with yAxis aggregation operation: $operation',
    async ({operation, expected}) => {
      const allColumnsStub = stubAllColumnsRef([statusColumn, effortColumn])
      const mockRequest = mockGetChartReponse(buildGetChartResponse())
      const queryClient = createTestQueryClient()

      const {result} = renderHook(
        () =>
          useChartSeries(
            defaultConfig(statusColumn.databaseId, effortColumn.databaseId, operation as MemexChartOperation),
          ),
        {
          wrapper: createWrapperWithContexts({
            QueryClient: {queryClient},
            ColumnsStable: createColumnsStableContext({allColumnsRef: allColumnsStub}),
          }),
        },
      )

      expect(result.current.isLoading).toBe(true)
      expect(result.current.series).toHaveLength(0)
      expect(result.current.xCoordinates).toHaveLength(0)

      await waitFor(() => {
        expect(mockRequest).toHaveBeenCalled()
      })

      expect(result.current.isLoading).toBe(false)
      expect(result.current.series).toHaveLength(1)
      expect(result.current.xCoordinates).toHaveLength(4)
      expect(result.current.series[0].name).toBe(expected)
      expect(result.current.series[0].data).toEqual([8, 4, 25, 13])
      expect(result.current.xCoordinates).toEqual(['Todo', 'In Progress', 'Done', 'No Status'])
    },
  )
})

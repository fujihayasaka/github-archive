import {renderHook, waitFor} from '@testing-library/react'

import type {MemexChartConfiguration} from '../../../client/api/charts/contracts/api'
import {useHistoricalChartSeries} from '../../../client/state-providers/charts/use-historical-chart-series'
import {stubGetChartRequest} from '../../mocks/api/memex-items'
import {createTestQueryClient} from '../../test-app-wrapper'
import {createWrapperWithContexts} from '../../wrapper-utils'

const defaultConfig: MemexChartConfiguration = {
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

const buildGetChartResponse = () => {
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
      {
        name: 'Closed pull requests',
        data: [2, 4, 3, 1],
      },
      {
        name: 'Not planned',
        data: [4, 3, 2, 1],
      },
      {
        name: 'Duplicate',
        data: [1, 2, 3, 4],
      },
    ],
    totalCount: 8,
  }
}

const mockGetChartReponse = () => {
  const response = buildGetChartResponse()
  return stubGetChartRequest(response)
}

describe('useHistoricalChartSeries', () => {
  beforeEach(() => {
    jest.useFakeTimers()
    jest.setSystemTime(new Date('2025-01-17T12:00:00Z'))
  })

  afterEach(() => {
    jest.useRealTimers()
  })

  it('makes a request to the charts API', async () => {
    const mockRequest = mockGetChartReponse()
    const queryClient = createTestQueryClient()

    const {result} = renderHook(() => useHistoricalChartSeries({configuration: defaultConfig}), {
      wrapper: createWrapperWithContexts({
        QueryClient: {queryClient},
      }),
    })

    expect(result.current.isLoading).toBe(true)
    expect(result.current.series).toHaveLength(0)
    expect(result.current.xCoordinates).toHaveLength(0)

    await waitFor(() => {
      expect(mockRequest).toHaveBeenCalled()
    })

    const expectedSeries = [
      {
        name: 'Open',
        data: [8, 4, 2, 1],
        fillColor: '#dafbe1',
        color: '#2da44e',
      },
      {
        name: 'Completed',
        data: [3, 1, 2, 4],
        fillColor: '#fbefff',
        color: '#8250df',
      },
      {
        name: 'Closed pull requests',
        data: [2, 4, 3, 1],
        fillColor: '#ffebe9',
        color: '#fa4549',
      },
      {
        name: 'Not planned',
        data: [4, 3, 2, 1],
        fillColor: '#f6f8fa',
        color: '#57606a',
      },
      {
        name: 'Duplicate',
        data: [1, 2, 3, 4],
        fillColor: '#f6f8fa',
        color: '#57606a',
      },
    ]

    expect(result.current.series).toHaveLength(5)
    expect(result.current.xCoordinates).toHaveLength(4)
    expect(result.current.isLoading).toBe(false)
    expect(result.current.xCoordinates).toEqual(['Dec 4 2024', 'Dec 31 2024', 'Jan 6', 'Jan 7'])

    for (const [index, s] of result.current.series.entries()) {
      const expected = expectedSeries[index]
      expect(s.name).toBe(expected.name)
      expect(s.data).toEqual(expected.data)
      expect(s.fillColor).toBe(expected.fillColor)
      expect(s.color).toBe(expected.color)
    }
  })
})

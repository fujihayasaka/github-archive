import {render} from '@testing-library/react'

import {MarkColor, type AreaChartProps} from '../ChartCard/types'
import {BaseAreaChart} from '../ChartCard/ChartByType/AreaChart'
import Chart from '../ChartCard/Chart'

jest.mock('../ChartCard/Chart', () => ({
  __esModule: true,
  default: jest.fn(() => null),
}))

describe('BaseAreaChart', () => {
  const baseProps: AreaChartProps = {
    options: {
      xAxis: {
        title: 'X Axis',
        categories: ['Category 1', 'Category 2', 'Category 3'],
      },
      yAxis: {
        title: 'Y Axis',
      },
    },
    series: [
      {name: 'A', data: [1, 2, 3]},
      {name: 'B', data: [4, 5, 6]},
    ],
  }

  beforeEach(() => {
    ;(Chart as jest.Mock).mockClear()
  })

  it('renders with more than 5 series and logs error in dev', () => {
    const oldEnv = process.env.NODE_ENV
    process.env.NODE_ENV = 'development'
    const errorSpy = jest.spyOn(console, 'error').mockImplementation(() => {})
    render(
      <BaseAreaChart
        {...baseProps}
        type="area"
        series={Array(6)
          .fill(0)
          .map((_, i) => ({name: `S${i}`, data: [i], colorByPoint: false}))}
      />,
    )
    expect(errorSpy).toHaveBeenCalledWith('Ideally, an area chart should contain no more than 5 lines.')
    errorSpy.mockRestore()
    process.env.NODE_ENV = oldEnv
  })

  // check the default color is rendered correctly
  it('renders with default color when no color is specified', () => {
    render(<BaseAreaChart {...baseProps} type="area" />)
    expect(Chart).toHaveBeenCalled()
    const chartProps = (Chart as jest.Mock).mock.calls[(Chart as jest.Mock).mock.calls.length - 1][0]
    expect(chartProps.series).toHaveLength(2)
    expect(chartProps.series[0].color).toBe(`var(${MarkColor.green})`)
    expect(chartProps.series[1].color).toBe(`var(${MarkColor.teal})`)
    expect(chartProps.series[0].fillColor).toBe('var(--display-green-scale-0)')
    expect(chartProps.series[1].fillColor).toBe('var(--display-teal-scale-0)')
  })

  // renders with custom colors when specified
  it('renders with custom colors when specified', () => {
    const customSeries = [
      {name: 'A', data: [1, 2, 3], color: 'purple' as const},
      {name: 'B', data: [4, 5, 6], color: 'yellow' as const},
    ]
    render(<BaseAreaChart {...baseProps} type="area" series={customSeries} />)
    expect(Chart).toHaveBeenCalled()
    const chartProps = (Chart as jest.Mock).mock.calls[(Chart as jest.Mock).mock.calls.length - 1][0]
    expect(chartProps.series[0].color).toBe(`var(${MarkColor.purple})`)
    expect(chartProps.series[1].color).toBe(`var(${MarkColor.yellow})`)
  })
})

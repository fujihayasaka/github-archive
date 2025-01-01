import {render} from '@testing-library/react'
import {BaseColumnChart, getTheme, getThemeBySeriesCount} from '../ChartCard/ChartByType/ColumnChart'
import type {BaseColumnChartProps} from '../ChartCard/types'
import Chart from '../ChartCard/Chart'

jest.mock('../ChartCard/Chart', () => ({
  __esModule: true,
  default: jest.fn(() => null),
}))

describe('BaseColumnChart', () => {
  const baseProps: BaseColumnChartProps<'column'> = {
    type: 'column',
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

  it('renders with more than 5 series and logs error in dev', () => {
    const oldEnv = process.env.NODE_ENV
    process.env.NODE_ENV = 'development'
    const errorSpy = jest.spyOn(console, 'error').mockImplementation(() => {})
    render(
      <BaseColumnChart
        {...baseProps}
        type="column"
        series={Array(6)
          .fill(0)
          .map((_, i) => ({name: `S${i}`, data: [i], colorByPoint: false}))}
      />,
    )
    expect(errorSpy).toHaveBeenCalledWith('Ideally, a column chart should contain no more than 5 segments or columns.')
    errorSpy.mockRestore()
    process.env.NODE_ENV = oldEnv
  })

  it('warns when stacking and colorByPoint are both set', () => {
    const warnSpy = jest.spyOn(console, 'warn').mockImplementation(() => {})
    render(
      <BaseColumnChart
        {...baseProps}
        type="column"
        stacking="normal"
        series={[
          {name: 'A', data: [1, 2, 3], colorByPoint: true},
          {name: 'B', data: [4, 5, 6], colorByPoint: true},
        ]}
      />,
    )
    expect(warnSpy).toHaveBeenCalledWith('Stacking is enabled, colorByPoint will be set to false for all series.')
    warnSpy.mockRestore()
  })

  it('check theme function', () => {
    const greenTheme = getTheme('green')
    expect(greenTheme).toStrictEqual([
      `var(--display-green-scale-9)`,
      `var(--display-green-scale-5)`,
      {
        linearGradient: {
          x1: 0,
          x2: 0,
          y1: 1,
          y2: 0,
        },
        stops: [
          [0.15, `var(--display-green-scale-0)`],
          [0.75, `var(--display-green-scale-2)`],
          [1, `var(--display-green-scale-4)`],
        ],
      },
      {
        linearGradient: {
          x1: 0,
          x2: 0,
          y1: 1,
          y2: 0,
        },
        stops: [
          [0.0, 'var(--bgColor-default)'],
          [0.5, `var(--display-green-scale-0)`],
          [1, `var(--display-green-scale-1)`],
        ],
      },
      `var(--display-green-scale-0)`,
    ])
    const blueTheme = getTheme('blue')
    expect(blueTheme).toStrictEqual([
      `var(--display-blue-scale-9)`,
      `var(--display-blue-scale-5)`,
      {
        linearGradient: {
          x1: 0,
          x2: 0,
          y1: 1,
          y2: 0,
        },
        stops: [
          [0.15, `var(--display-blue-scale-0)`],
          [0.75, `var(--display-blue-scale-2)`],
          [1, `var(--display-blue-scale-4)`],
        ],
      },
      {
        linearGradient: {
          x1: 0,
          x2: 0,
          y1: 1,
          y2: 0,
        },
        stops: [
          [0.0, 'var(--bgColor-default)'],
          [0.5, `var(--display-blue-scale-0)`],
          [1, `var(--display-blue-scale-1)`],
        ],
      },
      `var(--display-blue-scale-0)`,
    ])
  })

  it('getThemeBySeriesCount returns correct themes', () => {
    const theme = getThemeBySeriesCount(1, 'green')
    expect(theme).toEqual([getTheme('green')[0]])

    const theme2 = getThemeBySeriesCount(2, 'green')
    expect(theme2).toEqual([getTheme('green')[1], getTheme('green')[0]])

    const theme3 = getThemeBySeriesCount(3, 'green')
    expect(theme3).toEqual([getTheme('green')[2], getTheme('green')[1], getTheme('green')[0]])

    const theme4 = getThemeBySeriesCount(4, 'green')
    expect(theme4).toEqual([getTheme('green')[3], getTheme('green')[2], getTheme('green')[1], getTheme('green')[0]])

    const theme5 = getThemeBySeriesCount(5, 'green')
    expect(theme5).toEqual(getTheme('green').reverse())
  })

  // determine if the borders were properly set for 5 stacked series
  it('renders with 5 series and checks border colors', () => {
    render(
      <BaseColumnChart
        {...baseProps}
        theme="blue"
        type="column"
        series={[
          {name: 'A', data: [1, 2, 3], colorByPoint: false},
          {name: 'B', data: [4, 5, 6], colorByPoint: false},
          {name: 'C', data: [7, 8, 9], colorByPoint: false},
          {name: 'D', data: [10, 11, 12], colorByPoint: false},
          {name: 'E', data: [13, 14, 15], colorByPoint: false},
        ]}
      />,
    )
    expect(Chart).toHaveBeenCalled()
    // Get the last call's first argument (the Chart props)
    const chartProps = (Chart as jest.Mock).mock.calls[(Chart as jest.Mock).mock.calls.length - 1][0]
    expect(chartProps.type).toBe('column')
    expect(Array.isArray(chartProps.series)).toBe(true)
    // Check borderColor for each series
    expect(chartProps.series.map((s: {borderColor: string}) => s.borderColor)).toEqual([
      'var(--display-blue-scale-4)',
      'var(--display-blue-scale-4)',
      undefined,
      undefined,
      undefined,
    ])
    // Check dashStyle for the last two series
    expect(chartProps.series[1].dashStyle).toBe('ShortDash')
    expect(chartProps.series[0].dashStyle).toBe('Solid')
    jest.resetModules()
  })

  // renders with custom colors when specified
  it('renders with custom colors when specified', () => {
    const customSeries = [
      {name: 'A', data: [1, 2, 3]},
      {name: 'B', data: [4, 5, 6]},
    ]
    render(<BaseColumnChart {...baseProps} type="column" series={customSeries} colors={['purple', 'yellow']} />)
    expect(Chart).toHaveBeenCalled()
    const chartProps = (Chart as jest.Mock).mock.calls[(Chart as jest.Mock).mock.calls.length - 1][0]
    expect(chartProps.colors).toStrictEqual(['var(--display-purple-scale-5)', 'var(--display-yellow-scale-4)'])
  })
})

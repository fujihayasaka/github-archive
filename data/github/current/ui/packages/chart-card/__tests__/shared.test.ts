import {
  getDataWithDefaults,
  getXAxisOptionWithDefaults,
  getYAxisOptionsWithDefaults,
  getTransformedPlotOptions,
} from '../ChartCard/ChartByType/shared'
import type {ChartXAxisOptions, ChartYAxisOptions} from '../ChartCard/types'

describe('getDataWithDefaults', () => {
  it('should return empty array when no data is provided', () => {
    const result = getDataWithDefaults({series: [], type: 'line'})
    expect(result).toEqual([])
  })

  it('should return series with correct type and dashStyle', () => {
    const series = [
      {data: [1, 2, 3], name: 'Issues'},
      {data: [4, 5, 6], name: 'PRs'},
    ]
    const result = getDataWithDefaults({series, type: 'line'})
    expect(result).toEqual([
      {data: [1, 2, 3], marker: {symbol: 'circle'}, name: 'Issues', type: 'line', dashStyle: 'Solid'},
      {data: [4, 5, 6], marker: {symbol: 'square'}, name: 'PRs', type: 'line', dashStyle: 'ShortDash'},
    ])
  })

  it('check that dashStyles repeat', () => {
    const series = [
      {data: [1, 2, 3], name: 'Issues1'},
      {data: [4, 5, 6], name: 'Issues2'},
      {data: [7, 8, 9], name: 'Issues3'},
      {data: [10, 11, 12], name: 'Issues4'},
      {data: [13, 14, 15], name: 'Issues5'},
      {data: [16, 17, 18], name: 'Issues6'},
      {data: [19, 20, 21], name: 'Issues7'},
      {data: [22, 23, 24], name: 'Issues8'},
      {data: [25, 26, 27], name: 'Issues9'},
      {data: [28, 29, 30], name: 'Issues10'},
      {data: [31, 32, 33], name: 'Issues11'},
      {data: [34, 35, 36], name: 'Issues12'},
    ]

    const result = getDataWithDefaults({series, type: 'line'})
    expect(result).toEqual([
      {data: [1, 2, 3], marker: {symbol: 'circle'}, name: 'Issues1', type: 'line', dashStyle: 'Solid'},
      {data: [4, 5, 6], marker: {symbol: 'square'}, name: 'Issues2', type: 'line', dashStyle: 'ShortDash'},
      {data: [7, 8, 9], marker: {symbol: 'diamond'}, name: 'Issues3', type: 'line', dashStyle: 'Dot'},
      {data: [10, 11, 12], marker: {symbol: 'triangle'}, name: 'Issues4', type: 'line', dashStyle: 'DashDot'},
      {data: [13, 14, 15], marker: {symbol: 'triangle-down'}, name: 'Issues5', type: 'line', dashStyle: 'LongDash'},
      {data: [16, 17, 18], marker: {symbol: 'circle'}, name: 'Issues6', type: 'line', dashStyle: 'ShortDashDotDot'},
      {data: [19, 20, 21], marker: {symbol: 'square'}, name: 'Issues7', type: 'line', dashStyle: 'ShortDot'},
      {data: [22, 23, 24], marker: {symbol: 'diamond'}, name: 'Issues8', type: 'line', dashStyle: 'LongDashDot'},
      {data: [25, 26, 27], marker: {symbol: 'triangle'}, name: 'Issues9', type: 'line', dashStyle: 'Dash'},
      {
        data: [28, 29, 30],
        marker: {symbol: 'triangle-down'},
        name: 'Issues10',
        type: 'line',
        dashStyle: 'ShortDashDot',
      },
      {data: [31, 32, 33], marker: {symbol: 'circle'}, name: 'Issues11', type: 'line', dashStyle: 'LongDashDotDot'},
      {data: [34, 35, 36], marker: {symbol: 'square'}, name: 'Issues12', type: 'line', dashStyle: 'Solid'},
    ])
  })
})

describe('getXAxisOptionWithDefaults', () => {
  it('should return undefined when no options are provided', () => {
    const result = getXAxisOptionWithDefaults({})
    expect(result).toEqual(undefined)
  })

  it('should return xAxis with defaultDateFormat when datetime', () => {
    const xAxis = {
      title: 'X Axis',
      type: 'datetime',
    } as ChartXAxisOptions

    const result = getXAxisOptionWithDefaults({xAxis})
    expect(result).toMatchObject({
      title: {
        text: 'X Axis',
      },
      type: 'datetime',
      labels: {
        format: '{value:%b %e}',
      },
    })
  })

  it('should not return xAxis with defaultDateFormat when datetime', () => {
    const xAxis = {
      title: 'X Axis',
      type: 'category',
    } as ChartXAxisOptions

    const result = getXAxisOptionWithDefaults({xAxis})
    expect(result).toMatchObject({
      title: {
        text: 'X Axis',
      },
      type: 'category',
    })
  })

  it('should allow format override when datetime format is provided', () => {
    const xAxis = {
      title: 'X Axis',
      type: 'datetime',
      labels: {
        format: '{value:%b}',
      },
    } as ChartXAxisOptions

    const result = getXAxisOptionWithDefaults({xAxis})
    expect(result).toMatchObject({
      title: {
        text: 'X Axis',
      },
      labels: {
        format: '{value:%b}',
      },
      type: 'datetime',
    })
  })

  it('should allow format override when category format is provided', () => {
    const xAxis = {
      title: 'X Axis',
      type: 'category',
      labels: {
        format: '{value:%b}',
      },
    } as ChartXAxisOptions

    const result = getXAxisOptionWithDefaults({xAxis})
    expect(result).toMatchObject({
      title: {
        text: 'X Axis',
      },
      labels: {
        format: '{value:%b}',
      },
      type: 'category',
    })
  })
})

describe('getYAxisOptionsWithDefaults', () => {
  it('should return undefined when no options are provided', () => {
    const result = getYAxisOptionsWithDefaults({})
    expect(result).toEqual(undefined)
  })

  it('should return xAxis with defaultDateFormat when datetime', () => {
    const yAxis = {
      title: 'Y Axis',
      type: 'datetime',
    } as ChartYAxisOptions

    const result = getYAxisOptionsWithDefaults({yAxis})
    expect(result).toMatchObject([
      {
        title: {
          text: 'Y Axis',
        },
        type: 'datetime',
        labels: {
          format: '{value:%b %e}',
        },
      },
    ])
  })

  it('should not return xAxis with defaultDateFormat when datetime', () => {
    const yAxis = {
      title: 'Y Axis',
      type: 'category',
    } as ChartYAxisOptions

    const result = getYAxisOptionsWithDefaults({yAxis})
    expect(result).toMatchObject([
      {
        title: {
          text: 'Y Axis',
        },
        type: 'category',
      },
    ])
  })

  it('should allow format override when datetime format is provided', () => {
    const yAxis = {
      title: 'Y Axis',
      type: 'datetime',
      labels: {
        format: '{value:%b}',
      },
    } as ChartYAxisOptions

    const result = getYAxisOptionsWithDefaults({yAxis})
    expect(result).toMatchObject([
      {
        title: {
          text: 'Y Axis',
        },
        labels: {
          format: '{value:%b}',
        },
        type: 'datetime',
      },
    ])
  })

  it('should allow format override when category format is provided', () => {
    const yAxis = {
      title: 'Y Axis',
      type: 'category',
      labels: {
        format: '{value:%b}',
      },
    } as ChartYAxisOptions

    const result = getYAxisOptionsWithDefaults({yAxis})
    expect(result).toMatchObject([
      {
        title: {
          text: 'Y Axis',
        },
        labels: {
          format: '{value:%b}',
        },
        type: 'category',
      },
    ])
  })

  it('should work on arrays', () => {
    const yAxis = [
      {
        title: 'Y Axis',
        type: 'category',
        labels: {
          format: '{value:%b}',
        },
      },
      {
        type: 'datetime',
      },
    ] as ChartYAxisOptions[]

    const result = getYAxisOptionsWithDefaults({yAxis})
    expect(result).toMatchObject([
      {
        title: {
          text: 'Y Axis',
        },
        labels: {
          format: '{value:%b}',
        },
        type: 'category',
      },
      {
        type: 'datetime',
        labels: {
          format: '{value:%b %e}',
        },
      },
    ])
  })
})

describe('getTransformedPlotOptions', () => {
  it('should return marker enabled when marker is set to true', () => {
    const result = getTransformedPlotOptions({marker: true})
    expect(result).toEqual({
      series: {marker: {enabled: true}, dataLabels: {enabled: false}, lineWidth: 2, borderWidth: 1.5},
    })
  })

  it('should return marker disabled when marker is set to false', () => {
    const result = getTransformedPlotOptions({marker: false})
    expect(result).toEqual({
      series: {marker: {enabled: false}, dataLabels: {enabled: false}, lineWidth: 2, borderWidth: 1.5},
    })
  })

  it('should return dataLabel enabled when marker is set to true', () => {
    const result = getTransformedPlotOptions({labels: true})
    expect(result).toEqual({
      series: {marker: {enabled: false}, dataLabels: {enabled: true}, lineWidth: 2, borderWidth: 1.5},
    })
  })

  it('should return dataLabel disabled when marker is set to false', () => {
    const result = getTransformedPlotOptions({labels: false})
    expect(result).toEqual({
      series: {marker: {enabled: false}, dataLabels: {enabled: false}, lineWidth: 2, borderWidth: 1.5},
    })
  })

  it('should return marker with correct stacking', () => {
    const result = getTransformedPlotOptions({labels: false, stacking: 'normal'})
    expect(result).toEqual({
      series: {
        marker: {enabled: false},
        dataLabels: {enabled: false},
        lineWidth: 2,
        borderWidth: 1.5,
        stacking: 'normal',
      },
    })
  })

  it('should return plotOptions when plotOptions are provided', () => {
    const result = getTransformedPlotOptions({
      plotOptions: {
        pointStart: Date.UTC(2024, 1, 27, 0, 0, 0, 0),
        pointInterval: 24 * 3600 * 1000,
      },
      marker: true,
      stacking: 'percentage',
    })

    expect(result).toEqual({
      series: {
        pointStart: Date.UTC(2024, 1, 27, 0, 0, 0, 0),
        pointInterval: 24 * 3600 * 1000,
        marker: {enabled: true},
        dataLabels: {enabled: false},
        lineWidth: 2,
        borderWidth: 1.5,
        stacking: 'percentage',
      },
    })
  })
  describe('borderRadius', () => {
    it('should return plotOptions with noBorderRadius', () => {
      const result = getTransformedPlotOptions({noBorderRadius: true})
      expect(result).toEqual({
        series: {
          marker: {enabled: false},
          dataLabels: {enabled: false},
          lineWidth: 2,
          borderWidth: 1.5,
          borderRadius: 0,
        },
      })
    })
    it('should return plotOptions with default borderRadius', () => {
      const result = getTransformedPlotOptions({noBorderRadius: false})
      expect(result).toEqual({
        series: {marker: {enabled: false}, dataLabels: {enabled: false}, lineWidth: 2, borderWidth: 1.5},
      })
    })
  })
})

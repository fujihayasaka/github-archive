import type {ChartXAxisOptions, ChartYAxisOptions, PlotOptions, Stacking} from '../types'

export const isDev = () => process.env.NODE_ENV === 'development' || process.env.NODE_ENV === 'test'

export const SERIES_DASH_STYLES = [
  'Solid',
  'ShortDash',
  'Dot',
  'DashDot',
  'LongDash',
  'ShortDashDotDot',
  'ShortDot',
  'LongDashDot',
  'Dash',
  'ShortDashDot',
  'LongDashDotDot',
]

export const SYMBOLS = ['circle', 'square', 'diamond', 'triangle', 'triangle-down']

export const UNICODE_SYMBOLS_CONVERTED = {
  circle: '\u25CF',
  square: '\u25A0',
  diamond: '\u25C6',
  triangle: '\u25B2',
  'triangle-down': '\u25BC',
}
// abbreviated month followed by the day (no leading zero before days 1-9)
const DEFAULT_DATE_TIME_FORMAT = '{value:%b %e}'

const getDefaultFormat = (type: string | undefined) => (type === 'datetime' ? DEFAULT_DATE_TIME_FORMAT : undefined)

export const getXAxisOptionWithDefaults = ({
  xAxis,
  gridLineDashStyle,
  gridLineWidth,
}: {
  xAxis?: ChartXAxisOptions
  gridLineDashStyle?: Highcharts.DashStyleValue
  gridLineWidth?: number
}) => {
  if (xAxis === undefined) {
    return undefined
  }

  const title = xAxis.title

  return {
    // Allow user override
    gridLineWidth,
    ...xAxis,
    labels: {
      format: getDefaultFormat(xAxis.type),
      ...xAxis.labels,
    },
    title: {
      text: title,
    },
    gridLineDashStyle,
  }
}

export const getYAxisOptionsWithDefaults = ({
  yAxis,
  gridLineDashStyle,
  gridLineWidth,
}: {
  yAxis?: ChartYAxisOptions | ChartYAxisOptions[]
  gridLineDashStyle?: Highcharts.DashStyleValue
  gridLineWidth?: number
}) => {
  if (yAxis === undefined) {
    return undefined
  }

  // convert yAxis to an array if it is not already an array
  const array = Array.isArray(yAxis) ? yAxis : [yAxis]

  const isSingleYAxis = array.length === 1

  // map over yAxis and add default format to labels
  return array.map(yAxisOption => {
    const title = yAxisOption.title

    return {
      // Allow user override
      gridLineWidth: isSingleYAxis ? gridLineWidth : 0,
      ...yAxisOption,
      labels: {
        format: getDefaultFormat(yAxisOption.type),
        ...yAxisOption.labels,
      },
      title: {
        text: title,
      },
      gridLineDashStyle,
    }
  })
}

export const getDataWithDefaults = ({
  series,
  type,
  hasDashStyle = true,
}: {
  series: Highcharts.SeriesOptionsType[]
  type?: string
  hasDashStyle?: boolean
}) => {
  return (series ?? []).map((s, index) => {
    const dashStyle = SERIES_DASH_STYLES[index % SERIES_DASH_STYLES.length]
    // only set default dashStyle if it is not already set
    return {
      type,
      dashStyle: hasDashStyle ? dashStyle : undefined,
      marker: {
        symbol: SYMBOLS[index % SYMBOLS.length],
      },
      ...s,
    }
  })
}

// Default values for plotOptions
// - marker: false
// - dataLabel: false
// - lineWidth: 2 - only applied to line, area, areaspline and spline charts
// - borderWidth: 1.5 - only applied to bar column and pie charts
export const getTransformedPlotOptions = ({
  plotOptions,
  marker,
  labels,
  stacking,
  noBorderRadius = false,
}: {
  plotOptions?: PlotOptions
  marker?: boolean
  labels?: boolean
  stacking?: Stacking
  noBorderRadius?: boolean
}) => {
  const defaultPlotOptions = {
    marker: {enabled: marker ?? false},
    dataLabels: {enabled: labels ?? false},
    lineWidth: 2,
    borderWidth: 1.5,
    stacking: stacking ?? undefined,
    borderRadius: noBorderRadius ? 0 : undefined,
  }

  return {
    series: {...plotOptions, ...defaultPlotOptions},
  } as Highcharts.PlotOptions
}

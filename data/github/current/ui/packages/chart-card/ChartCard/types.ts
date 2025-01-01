export const MarkColor = {
  auburn: '--display-auburn-scale-6',
  blue: '--display-blue-scale-4',
  brown: '--display-brown-scale-5',
  coral: '--display-coral-scale-5',
  cyan: '--display-cyan-scale-5',
  gray: '--display-gray-scale-5',
  green: '--display-green-scale-4',
  indigo: '--display-indigo-scale-7',
  lemon: '--display-lemon-scale-4',
  lime: '--display-lime-scale-4',
  olive: '--display-olive-scale-5',
  orange: '--display-orange-scale-4',
  pine: '--display-pine-scale-5',
  pink: '--display-pink-scale-5',
  plum: '--display-plum-scale-7',
  purple: '--display-purple-scale-5',
  red: '--display-red-scale-6',
  teal: '--display-teal-scale-4',
  yellow: '--display-yellow-scale-4',
} as const

export type Colors = keyof typeof MarkColor

export type MarkColor = (typeof MarkColor)[keyof typeof MarkColor]

type ChartXAxisOptionDateTime = Omit<Highcharts.XAxisOptions, 'gridLineDashStyle' | 'title' | 'type'> & {
  type: 'datetime'
  title?: string
}

type ChartXAxisOptionsNoDateTime = Omit<Highcharts.XAxisOptions, 'gridLineDashStyle' | 'title'> & {
  title: string
}

type ChartYAxisOptionsDateTime = Omit<Highcharts.XAxisOptions, 'gridLineDashStyle' | 'title' | 'type'> & {
  type: 'datetime'
  title?: string
}

type ChartYAxisOptionsNoDateTime = Omit<Highcharts.YAxisOptions, 'gridLineDashStyle' | 'title'> & {
  title: string
}

export type ChartYAxisOptions = ChartYAxisOptionsDateTime | ChartYAxisOptionsNoDateTime

export type ChartXAxisOptions = ChartXAxisOptionDateTime | ChartXAxisOptionsNoDateTime

type Series = {
  data: number[] | number[][]
  name: string
  yAxis?: number
  color?: Colors
  colorByPoint?: boolean
  negativeColor?: Colors
}

export type PlotOptions = {
  pointStart?: number | Date
  pointInterval?: number
  animation?: boolean
  pointPlacement?: 'on' | 'between' | number
  stacking?: 'normal' | 'percent'
}

// Line Chart & Spline Chart
export type BaseLineChartProps<T extends 'line' | 'spline'> = {
  type: T
  options?: {
    xAxis?: ChartXAxisOptions
    yAxis?: ChartYAxisOptions | ChartYAxisOptions[]
    plot?: PlotOptions
  }
  marker?: boolean
  series?: Series[]
  labels?: boolean
  overrideOptionsNotRecommended?: Highcharts.Options
}

export type LineChartProps = Omit<BaseLineChartProps<'line'>, 'type'>
export type SplineChartProps = Omit<BaseLineChartProps<'spline'>, 'type'>

export type Stacking = 'normal' | 'percentage'

// Area Chart & AreaSpline Chart
export type BaseAreaChartProps<T extends 'area' | 'areaspline'> = {
  type: T
  options?: {
    xAxis?: ChartXAxisOptions
    yAxis?: ChartYAxisOptions | ChartYAxisOptions[]
    plot?: PlotOptions
  }
  marker?: boolean
  series?: Series[]
  labels?: boolean
  showRangeSelector?: boolean
  stacking?: Stacking
  overrideOptionsNotRecommended?: Highcharts.Options
}

export type AreaChartProps = Omit<BaseAreaChartProps<'area'>, 'type'>
export type AreaSplineChartProps = Omit<BaseAreaChartProps<'areaspline'>, 'type'>

export type Theme = 'green' | 'pine' | 'teal' | 'cyan' | 'blue' | 'indigo' | 'purple' | 'orange'
export type ColumnChartTheme = {
  colors?: never
  theme?: Theme
}

export type ColumnChartColors = {
  colors?: Colors[]
  theme?: never
}

export type BaseColumnChartProps<T extends 'bar' | 'column'> = {
  type: T
  options?: {
    xAxis?: ChartXAxisOptions
    yAxis?: ChartYAxisOptions | ChartYAxisOptions[]
    plot?: PlotOptions
  }
  series?: Array<Omit<Series, 'color' | 'negativeColor'>>
  labels?: boolean
  stacking?: Stacking
  overrideOptionsNotRecommended?: Highcharts.Options
}

export type ColumnChartStyles = ColumnChartTheme | ColumnChartColors

export type BarChartProps = Omit<BaseColumnChartProps<'bar'>, 'type'> & ColumnChartStyles

export type ColumnChartProps = Omit<BaseColumnChartProps<'column'>, 'type'> & ColumnChartStyles

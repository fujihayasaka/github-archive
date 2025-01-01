import {BaseLineChart} from './LineChart'
import type {SplineChartProps} from '../types'

const SplineChart = (props: SplineChartProps) => {
  return <BaseLineChart {...props} type="spline" />
}

export default SplineChart

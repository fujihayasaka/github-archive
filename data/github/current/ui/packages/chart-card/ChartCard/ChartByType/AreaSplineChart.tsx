import {BaseAreaChart} from './AreaChart'
import type {AreaSplineChartProps} from '../types'

const AreaSplineChart = (props: AreaSplineChartProps) => {
  return <BaseAreaChart {...props} type="areaspline" />
}

export default AreaSplineChart

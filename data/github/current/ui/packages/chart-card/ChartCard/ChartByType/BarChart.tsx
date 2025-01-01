import type {BarChartProps} from '../types'
import {BaseColumnChart} from './ColumnChart'

const BarChart = (props: BarChartProps) => {
  return <BaseColumnChart {...props} type="bar" />
}

export default BarChart

import type {Meta, StoryObj} from '@storybook/react'

import type {BarChartProps, ColumnChartProps} from '../../ChartCard/types'
import BarChartComponent from '../../ChartCard/ChartByType/BarChart'

const meta: Meta<typeof BarChartComponent> = {
  title: 'Recipes/ChartCard/SubComponents/BarChart',
  component: BarChartComponent,
}

export default meta

export const BarChart: StoryObj<BarChartProps> = {
  args: {
    labels: true,
    options: {
      xAxis: {
        categories: ['Low', 'Medium', 'High', 'Critical'],
        title: 'Time',
      },
      yAxis: {title: 'Billing'},
    },
    series: [
      {
        name: 'User A Usage',
        data: [2100, 9000, 7600, 1700],
        colorByPoint: false,
      },
      {
        name: 'User B Usage',
        data: [2456, 3000, 9000, 4800],
        colorByPoint: false,
      },
    ],
    stacking: undefined,
    colors: ['pink', 'blue'],
  },
  render: (args: ColumnChartProps) => (
    <BarChartComponent
      series={args.series}
      options={{
        xAxis: args.options?.xAxis,
        yAxis: args.options?.yAxis,
        plot: args.options?.plot,
      }}
      stacking={args.stacking}
      labels={args.labels}
      colors={args.colors}
    />
  ),
}
BarChart.storyName = 'BarChart'

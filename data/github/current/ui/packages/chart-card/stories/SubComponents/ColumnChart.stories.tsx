import type {Meta, StoryObj} from '@storybook/react'

import type {ColumnChartProps} from '../../ChartCard/types'
import ColumnChartComponent from '../../ChartCard/ChartByType/ColumnChart'

const meta: Meta<typeof ColumnChartComponent> = {
  title: 'Recipes/ChartCard/SubComponents/ColumnChart',
  component: ColumnChartComponent,
}

export default meta

export const ColumnChart: StoryObj<ColumnChartProps> = {
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
        colorByPoint: true,
      },
    ],
    stacking: undefined,
    colors: ['pine', 'cyan', 'indigo', 'purple', 'orange'],
  },
  render: (args: ColumnChartProps) => (
    <ColumnChartComponent
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

ColumnChart.storyName = 'ColumnChart'

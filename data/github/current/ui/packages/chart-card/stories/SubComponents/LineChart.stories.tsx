import type {Meta, StoryObj} from '@storybook/react'

import type {LineChartProps} from '../../ChartCard/types'
import LineChartComponent from '../../ChartCard/ChartByType/LineChart'

const meta: Meta<typeof LineChartComponent> = {
  title: 'Recipes/ChartCard/SubComponents/LineChart',
  component: LineChartComponent,
}

export default meta

export const LineChart: StoryObj<LineChartProps> = {
  args: {
    labels: true,
    marker: true,
    options: {
      xAxis: {
        type: 'datetime',
        labels: {
          format: 'Jan {value}',
        },
        title: 'Time',
      },
      yAxis: {title: 'Issues'},
      plot: {
        pointStart: 2012,
      },
    },
    series: [
      {
        name: 'Issues',
        data: [1, 2, 1, 4, 3, 6, 5, 3, 2, 12],
        color: 'orange',
      },
      {
        name: 'Pull Requests',
        data: [3, 12, 5, 7, 6, 11, 2, 9, 1, 10],
        color: 'blue',
      },
    ],
  },
  render: (args: LineChartProps) => (
    <LineChartComponent
      series={args.series}
      options={{
        xAxis: args.options?.xAxis,
        yAxis: args.options?.yAxis,
        plot: args.options?.plot,
      }}
      marker={args.marker}
      labels={args.labels}
    />
  ),
}
LineChart.storyName = 'LineChart'

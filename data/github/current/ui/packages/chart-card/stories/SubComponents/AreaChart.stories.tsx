import type {Meta, StoryObj} from '@storybook/react'

import type {AreaChartProps} from '../../ChartCard/types'
import AreaChartComponent from '../../ChartCard/ChartByType/AreaChart'

const meta: Meta<typeof AreaChartComponent> = {
  title: 'Recipes/ChartCard/SubComponents/AreaChart',
  component: AreaChartComponent,
}

export default meta

export const AreaChart: StoryObj<AreaChartProps> = {
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
        color: 'yellow',
      },
      {
        name: 'Pull Requests',
        data: [3, 12, 5, 7, 6, 11, 2, 9, 1, 10],
        color: 'purple',
      },
    ],
    stacking: 'normal',
  },
  render: (args: AreaChartProps) => (
    <AreaChartComponent
      series={args.series}
      options={{
        xAxis: args.options?.xAxis,
        yAxis: args.options?.yAxis,
        plot: args.options?.plot,
      }}
      marker={args.marker}
      stacking={args.stacking}
      labels={args.labels}
    />
  ),
}
AreaChart.storyName = 'AreaChart'

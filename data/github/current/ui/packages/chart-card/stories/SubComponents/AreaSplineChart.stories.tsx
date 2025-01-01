import type {Meta, StoryObj} from '@storybook/react'

import type {AreaSplineChartProps} from '../../ChartCard/types'
import AreaSplineChartComponent from '../../ChartCard/ChartByType/AreaSplineChart'

const meta: Meta<typeof AreaSplineChartComponent> = {
  title: 'Recipes/ChartCard/SubComponents/AreaSplineChart',
  component: AreaSplineChartComponent,
}

export default meta

export const AreaSplineChart: StoryObj<AreaSplineChartProps> = {
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
        color: 'green',
      },
      {
        name: 'Pull Requests',
        data: [3, 12, 5, 7, 6, 11, 2, 9, 1, 10],
        color: 'teal',
      },
    ],
    stacking: 'normal',
  },
  render: (args: AreaSplineChartProps) => (
    <AreaSplineChartComponent
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
AreaSplineChart.storyName = 'AreaSplineChart'

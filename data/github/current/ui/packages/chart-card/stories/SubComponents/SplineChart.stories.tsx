import type {Meta, StoryObj} from '@storybook/react'
import type {SplineChartProps} from '../../ChartCard/types'
import SplineChartComponent from '../../ChartCard/ChartByType/SplineChart'

const meta: Meta<typeof SplineChartComponent> = {
  title: 'Recipes/ChartCard/SubComponents/SplineChart',
  component: SplineChartComponent,
}

export default meta

export const SplineChart: StoryObj<SplineChartProps> = {
  args: {
    labels: true,
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
        color: 'red',
      },
      {
        name: 'Pull Requests',
        data: [3, 12, 5, 7, 6, 11, 2, 9, 1, 10],
        color: 'plum',
      },
    ],
    marker: true,
  },
  render: (args: SplineChartProps) => (
    <SplineChartComponent
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
SplineChart.storyName = 'SplineChart'

import type {Meta, StoryObj} from '@storybook/react'
import {ChartCard, type ChartCardProps} from '../ChartCard'

const meta: Meta<
  | typeof ChartCard
  | typeof ChartCard.Title
  | typeof ChartCard.Chart
  | typeof ChartCard.Description
  | typeof ChartCard.LeadingVisual
  | typeof ChartCard.LineChart
  | typeof ChartCard.TrailingVisual
  | typeof ChartCard.SplineChart
  | typeof ChartCard.AreaChart
  | typeof ChartCard.AreaSplineChart
  | typeof ChartCard.ColumnChart
  | typeof ChartCard.BarChart
> = {
  title: 'Recipes/ChartCard',
  component: ChartCard,
  subcomponents: {
    Title: ChartCard.Title,
    Description: ChartCard.Description,
    LeadingVisual: ChartCard.LeadingVisual,
    TrailingVisual: ChartCard.TrailingVisual,
    Chart: ChartCard.Chart,
    LineChart: ChartCard.LineChart,
    SplineChart: ChartCard.SplineChart,
    AreaChart: ChartCard.AreaChart,
    AreaSplineChart: ChartCard.AreaSplineChart,
    ColumnChart: ChartCard.ColumnChart,
    BarChart: ChartCard.BarChart,
  },
  parameters: {
    controls: {expanded: true, sort: 'requiredFirst'},
  },
}

export default meta

export const Example: StoryObj<ChartCardProps> = {
  args: {
    size: 'medium',
    border: true,
    padding: 'normal',
    visibleControls: true,
  },
  render: (args: ChartCardProps) => (
    <ChartCard {...args}>
      <ChartCard.Title>Accessible Chart</ChartCard.Title>
      <ChartCard.Description>Chart of issues over time</ChartCard.Description>
      <ChartCard.LineChart
        series={[
          {
            name: 'Issues',
            data: [1, 2, 1, 4, 3, 6, 5, 3, 2, 12],
          },
          {
            name: 'Pull Requests',
            data: [3, 12, 5, 7, 6, 11, 2, 9, 1, 10],
          },
        ]}
        options={{
          xAxis: {
            type: 'datetime',
            labels: {
              format: 'Jan {value}',
            },
            title: 'Time',
          },
          yAxis: {
            labels: {
              formatter: ({value}) => `${value} issues`,
            },
            title: 'Issues',
          },
          plot: {
            pointStart: 2012,
          },
        }}
      />
    </ChartCard>
  ),
}
Example.storyName = 'ChartCard'

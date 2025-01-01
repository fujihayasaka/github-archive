import type {Meta, StoryObj} from '@storybook/react'
import {ChartCard, type ChartCardProps} from '../../../ChartCard'

const meta = {
  title: 'Recipes/ChartCard/Examples/Repos Insights',
  component: ChartCard,
  parameters: {
    controls: {disable: true, exclude: /.*/g}, // Hide controls, since this story should already be using the correct values
  },
} satisfies Meta<React.ComponentProps<typeof ChartCard>>
export default meta

export const ContributionActivity: StoryObj<ChartCardProps> = {
  args: {
    size: 'large',
    border: true,
    padding: 'normal',
    visibleControls: true,
  },
  render: (args: ChartCardProps) => (
    <ChartCard {...args}>
      <ChartCard.Title>Contribution activity</ChartCard.Title>
      <ChartCard.Description>Count of total contribution activity to Discussions, Issues and PRs</ChartCard.Description>
      <ChartCard.LineChart
        series={[
          {
            name: 'Discussions',
            data: [70, 30, 55, 70, 35, 0],
          },
          {
            name: 'Issues',
            data: [3, 1, 2, 3, 4, 0],
          },
          {
            name: 'Pull Requests',
            data: [2, 1, 3, 5, 4, 0],
          },
        ]}
        options={{
          xAxis: {
            type: 'datetime',
            title: 'Timeline',
          },
          yAxis: {
            title: 'Quantity',
          },
          plot: {
            pointStart: Date.UTC(2024, 1, 8, 0, 0, 0, 0),
            pointInterval: 7 * 24 * 3600 * 1000, // seven days
          },
        }}
        marker={false}
      />
    </ChartCard>
  ),
}
ContributionActivity.storyName = 'Community — Contribution Activity (Line Chart)'

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

export const GitClones: StoryObj<ChartCardProps> = {
  args: {
    size: 'large',
    border: true,
    padding: 'normal',
    visibleControls: true,
  },
  render: (args: ChartCardProps) => (
    <ChartCard {...args}>
      <ChartCard.Title>Git clones</ChartCard.Title>
      <ChartCard.LineChart
        series={[
          {
            name: 'Clones',
            data: [180, 190, 210, 250, 50, 47, 200, 190, 175, 120, 170, 100, 90, 200],
            yAxis: 0,
          },
          {
            name: 'Unique cloners',
            data: [3, 3, 3, 3, 3, 2, 3, 5, 3, 3, 3, 3, 2, 3],
            yAxis: 1,
          },
        ]}
        options={{
          xAxis: {
            type: 'datetime',
            labels: {
              format: '{value:%m/%e}',
            },
            tickAmount: 14,
            tickInterval: 24 * 3600 * 1000,
            tickmarkPlacement: 'on',
            lineColor: 'transparent',
          },
          yAxis: [
            {
              // Primary yAxis
              title: 'Clones',
              max: 260,
              tickInterval: 20,
              endOnTick: true,
              lineColor: 'var(--data-blue-color-emphasis, var(--data-blue-color))',
              lineWidth: 2.5,
              offset: -10,
            },
            {
              // Secondary yAxis
              title: 'Unique cloners',
              opposite: true,
              // gridLineWidth: 0,
              max: 8,
              lineColor: 'var(--data-green-color-emphasis, var(--data-green-color))',
              lineWidth: 2.5,
              offset: -10,
            },
          ],
          plot: {
            pointStart: Date.UTC(2024, 1, 27, 0, 0, 0, 0),
            pointInterval: 24 * 3600 * 1000, // one day
          },
        }}
        marker
      />
    </ChartCard>
  ),
}
GitClones.storyName = 'Traffic — Git Clones (Line Chart)'

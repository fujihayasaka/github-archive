import type {Meta} from '@storybook/react'
import {ChartCard, type ChartCardProps} from '../../ChartCard'

const meta = {
  title: 'Recipes/ChartCard/Stress Cases',
  component: ChartCard,
  parameters: {
    controls: {expanded: true, sort: 'requiredFirst'},
  },
} satisfies Meta<React.ComponentProps<typeof ChartCard>>
export default meta

export const ChartWithManySeries = {
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
            name: 'Pull Requests',
            data: [3, 12, 5, 7, 6, 11, 2, 9, 1, 10],
          },
          {
            name: 'Pull Requests 2',
            data: [3, 12, 5, 7, 6, 11, 2, 9, 1, 10].map(x => x + 2),
          },
          {
            name: 'Pull Requests 3',
            data: [3, 12, 5, 7, 6, 11, 2, 9, 1, 10].map(x => x + 4),
          },
          {
            name: 'Pull Requests 4',
            data: [3, 12, 5, 7, 6, 11, 2, 9, 1, 10].map(x => x + 6),
          },
          {
            name: 'Pull Requests 5',
            data: [3, 12, 5, 7, 6, 11, 2, 9, 1, 10].map(x => x + 8),
          },
          {
            name: 'Pull Requests 6',
            data: [3, 12, 5, 7, 6, 11, 2, 9, 1, 10].map(x => x + 10),
          },
          {
            name: 'Pull Requests 7',
            data: [3, 12, 5, 7, 6, 11, 2, 9, 1, 10].map(x => x + 12),
          },
          {
            name: 'Pull Requests 8',
            data: [3, 12, 5, 7, 6, 11, 2, 9, 1, 10].map(x => x + 14),
          },
          {
            name: 'Pull Requests 9',
            data: [3, 12, 5, 7, 6, 11, 2, 9, 1, 10].map(x => x + 16),
          },
          {
            name: 'Pull Requests 10',
            data: [3, 12, 5, 7, 6, 11, 2, 9, 1, 10].map(x => x + 18),
          },
          {
            name: 'Pull Requests 11',
            data: [3, 12, 5, 7, 6, 11, 2, 9, 1, 10].map(x => x + 20),
          },
          {
            name: 'Pull Requests 12',
            data: [3, 12, 5, 7, 6, 11, 2, 9, 1, 10].map(x => x + 22),
          },
        ]}
        options={{
          xAxis: {
            title: 'Time',
          },
          yAxis: {
            title: 'Pull Requests',
          },
          plot: {
            pointStart: 2012,
          },
        }}
        marker
      />
    </ChartCard>
  ),
}

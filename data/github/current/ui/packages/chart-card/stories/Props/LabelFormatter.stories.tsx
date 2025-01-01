import type {Meta, StoryObj} from '@storybook/react'
import {ChartCard, type ChartCardProps} from '../../ChartCard'

const meta = {
  title: 'Recipes/ChartCard/Props/Labels with avatars',
  component: ChartCard,
  parameters: {
    controls: {disable: true, exclude: /.*/g}, // Hide controls, since this story should already be using the correct values
  },
} satisfies Meta<React.ComponentProps<typeof ChartCard>>
export default meta

export const LabelsWithAvatars: StoryObj<ChartCardProps> = {
  args: {
    size: 'medium',
    border: true,
    padding: 'normal',
    visibleControls: true,
  },
  render: (args: ChartCardProps) => (
    <ChartCard {...args}>
      <ChartCard.Title>Commits per user</ChartCard.Title>
      <ChartCard.ColumnChart
        series={[
          {
            name: 'Commits',
            data: [502, 489, 461, 437],
          },
        ]}
        options={{
          xAxis: {
            title: 'Users',
            categories: ['tbenning', 'smockle', 'andrialexandrou', 'ansballard'],
            labels: {
              useHTML: true,
              formatter: () => {
                const images = {
                  tbenning: 'https://avatars.githubusercontent.com/u/7265547?s=60&amp;v=4',
                  smockle: 'https://avatars.githubusercontent.com/u/3104489?s=60&amp;v=4',
                  andrialexandrou: 'https://avatars.githubusercontent.com/u/14981214?s=60&amp;v=4',
                  ansballard: 'https://avatars.githubusercontent.com/u/3535127?s=60&amp;v=4',
                }
                // eslint-disable-next-line github/unescaped-html-literal
                return `<div style="text-align: center;">
                          <img src="${
                            // eslint-disable-next-line  @typescript-eslint/no-invalid-this
                            images[(this ?? {value: ''}).value as keyof typeof images]
                            // eslint-disable-next-line @typescript-eslint/no-invalid-this
                          }" style="height: 50px; width: 50px;" alt="${(this ?? {value: ''}).value}" />
                        </div>`
              },
            },
          },
          yAxis: {
            title: 'Commits',
          },
        }}
      />
    </ChartCard>
  ),
}
LabelsWithAvatars.storyName = 'Labels with avatars'

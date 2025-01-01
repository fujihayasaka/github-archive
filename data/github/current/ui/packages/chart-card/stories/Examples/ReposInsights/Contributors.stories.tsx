import type {Meta, StoryObj} from '@storybook/react'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {ChartCard, type ChartCardProps} from '../../../ChartCard'
import {Label} from '@primer/react'
import {within, expect, userEvent} from '@storybook/test'
import {shouldInteractionPlay} from '@github-ui/storybook'

import styles from './Contributors.stories.module.css'

const meta = {
  title: 'Recipes/ChartCard/Examples/Repos Insights',
  component: ChartCard,
  parameters: {
    controls: {disable: true, exclude: /.*/g}, // Hide controls, since this story should already be using the correct values
  },
} satisfies Meta<React.ComponentProps<typeof ChartCard>>
export default meta

const thousandDataPoints = () => {
  const dataPoints: Array<[number, number]> = []
  for (
    let date = Date.parse('1950-01-01'), value = Math.floor(Math.random() * 40);
    dataPoints.length <= 1000;
    date = date + 86400000, value = Math.max(0, value + Math.floor(Math.random() * 10) - 5)
  ) {
    if (dataPoints.length === 0) value = 50
    if (dataPoints.length === 1) value = 100
    dataPoints.push([date, value])
  }
  return dataPoints
}

export const Contributors: StoryObj<ChartCardProps> = {
  args: {
    size: 'small',
    border: true,
    padding: 'normal',
    visibleControls: true,
  },
  render: (args: ChartCardProps) => {
    // prettier-ignore
    const users = [
      {
        username: 'tbenning',
        avatarUrl: 'https://avatars.githubusercontent.com/u/7265547?s=60&amp;v=4',
        totalCommits: 502,
        data: thousandDataPoints(),
      },
      {
        username: 'smockle',
        avatarUrl: 'https://avatars.githubusercontent.com/u/3104489?s=60&amp;v=4',
        totalCommits: 489,
        data: [
          [1688342400000, 6],[1688428800000, 1],[1688515200000, 8],[1688601600000, 4],[1688688000000, 0],[1688774400000, 0],[1688860800000, 6],[1688947200000, 13],[1689033600000, 6],[1689120000000, 7],[1689206400000, 9],[1689292800000, 15],[1689379200000, 15],[1689465600000, 8],[1689552000000, 13],[1689638400000, 7],[1689724800000, 2],[1689811200000, 1],[1689897600000, 0],[1689984000000, 2],[1690070400000, 9],[1690156800000, 6],[1690243200000, 11],[1690329600000, 9],[1690416000000, 3],[1690502400000, 7],[1690588800000, 10],[1690675200000, 8],[1690761600000, 9],[1690848000000, 3],[1690934400000, 2],[1691020800000, 0],[1691107200000, 3],[1691193600000, 3],[1691280000000, 7],[1691366400000, 5],[1691452800000, 10],[1691539200000, 10],[1691625600000, 16],[1691712000000, 9],[1691798400000, 10],[1691884800000, 4],[1691971200000, 9],[1692057600000, 15],[1692144000000, 21],[1692230400000, 14],[1692316800000, 19],[1692403200000, 19],[1692489600000, 25],[1692576000000, 28]
        ]
      },
      {
        username: 'andrialexandrou',
        avatarUrl: 'https://avatars.githubusercontent.com/u/14981214?s=60&amp;v=4',
        totalCommits: 461,
        data: [
          [1688342400000, 14],[1688428800000, 11],[1688515200000, 7],[1688601600000, 13],[1688688000000, 18],[1688774400000, 25],[1688860800000, 20],[1688947200000, 14],[1689033600000, 10],[1689120000000, 12],[1689206400000, 12],[1689292800000, 8],[1689379200000, 9],[1689465600000, 4],[1689552000000, 5],[1689638400000, 4],[1689724800000, 0],[1689811200000, 0],[1689897600000, 0],[1689984000000, 4],[1690070400000, 3],[1690156800000, 0],[1690243200000, 0],[1690329600000, 4],[1690416000000, 0],[1690502400000, 0],[1690588800000, 0],[1690675200000, 0],[1690761600000, 0],[1690848000000, 0],[1690934400000, 0],[1691020800000, 0],[1691107200000, 3],[1691193600000, 10],[1691280000000, 16],[1691366400000, 20],[1691452800000, 23],[1691539200000, 24],[1691625600000, 17],[1691712000000, 19],[1691798400000, 13],[1691884800000, 15],[1691971200000, 18],[1692057600000, 17],[1692144000000, 24],[1692230400000, 23],[1692316800000, 16],[1692403200000, 21],[1692489600000, 19],[1692576000000, 20]
          ]
      },
      {
        username: 'ansballard',
        avatarUrl: "https://avatars.githubusercontent.com/u/3535127?s=60&amp;v=4",
        totalCommits: 437,
        data: [
          [1688342400000, 40],[1688428800000, 40],[1688515200000, 38],[1688601600000, 34],[1688688000000, 32],[1688774400000, 30],[1688860800000, 37],[1688947200000, 33],[1689033600000, 34],[1689120000000, 30],[1689206400000, 35],[1689292800000, 40],[1689379200000, 40],[1689465600000, 40],[1689552000000, 40],[1689638400000, 40],[1689724800000, 39],[1689811200000, 39],[1689897600000, 38],[1689984000000, 36],[1690070400000, 40],[1690156800000, 38],[1690243200000, 40],[1690329600000, 39],[1690416000000, 40],[1690502400000, 35],[1690588800000, 35],[1690675200000, 30],[1690761600000, 33],[1690848000000, 30],[1690934400000, 34],[1691020800000, 32],[1691107200000, 34],[1691193600000, 40],[1691280000000, 35],[1691366400000, 35],[1691452800000, 40],[1691539200000, 34],[1691625600000, 40],[1691712000000, 40],[1691798400000, 35],[1691884800000, 30],[1691971200000, 30],[1692057600000, 36],[1692144000000, 32],[1692230400000, 30],[1692316800000, 27],[1692403200000, 30],[1692489600000, 28],[1692576000000, 26]
          ]
      }
    ]
    return (
      <div className={styles.ContributorsGridContainer}>
        {users.map(({username, avatarUrl, totalCommits, data}, index) => (
          <ChartCard
            {...args}
            // eslint-disable-next-line @eslint-react/no-array-index-key
            key={index}
          >
            <ChartCard.LeadingVisual>
              <GitHubAvatar src={avatarUrl} size={40} />
            </ChartCard.LeadingVisual>
            <ChartCard.Title as="h4" className={styles.ContributorsChartCardTitle}>
              {username}
            </ChartCard.Title>
            <ChartCard.Description className={styles.ContributorsChartCardTitle}>
              {totalCommits} commits
            </ChartCard.Description>
            <ChartCard.TrailingVisual>
              <Label>#{index + 1}</Label>
            </ChartCard.TrailingVisual>
            <ChartCard.AreaSplineChart
              series={[
                {
                  name: 'Commits',
                  data,
                },
              ]}
              options={{
                xAxis: {
                  type: 'datetime',
                  title: 'Date',
                },
                yAxis: {
                  title: 'Commits',
                },
              }}
              marker={false}
            />
          </ChartCard>
        ))}
      </div>
    )
  },
  play: async ({canvasElement, step}) => {
    if (shouldInteractionPlay()) {
      const canvas = within(canvasElement)

      // make sure the charts have fully loaded
      expect(await canvas.queryAllByRole('application').length).toBe(4)

      await step(
        'assert that live region is used to announce points when total data points is above threshold',
        async () => {
          const user = await userEvent.setup()
          const tbenningChart = await canvas.findByRole('region', {name: 'tbenning. Interactive chart.'})
          await expect(within(tbenningChart).queryAllByRole('img').length).toBe(0)
          const liveRegionContainer = await canvas.getByTestId('sr-assertive')
          await expect(liveRegionContainer).toHaveTextContent('')
          await user.tab()
          await user.tab()

          const applicationRole = within(tbenningChart).getByRole('application')
          await expect(applicationRole).toHaveFocus()
          await expect(liveRegionContainer).toHaveTextContent('Sunday, 1 Jan 1950, 50. Commits.')
        },
      )

      await step(
        'assert that image elements with accessible names are rendered when total data points are below default/configured threshold',
        async () => {
          const smockleChart = await canvas.findByRole('region', {name: 'smockle. Interactive chart.'})
          await expect(within(smockleChart).queryAllByRole('img').length).toBe(50)
          await expect(
            within(smockleChart).getByRole('img', {name: 'Monday, 3 Jul 2023, 6. Commits.'}),
          ).toBeInTheDocument()
        },
      )
    }
  },
}
Contributors.storyName = 'Contributors (Areaspline Charts)'

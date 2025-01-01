import type {Meta, StoryObj} from '@storybook/react'
import {Box} from '@primer/react'
import {ChartCard, type ChartCardProps} from '../../../ChartCard'
import {ChartWithRangeSelector} from './ChartWithRangeSelector'
import {PeriodMenu} from './PeriodMenu'
import {DateProvider} from './DateContext'
import {within, expect, userEvent} from '@storybook/test'

const meta = {
  title: 'Recipes/ChartCard/Props',
  component: ChartCard,
  parameters: {
    controls: {expanded: true, sort: 'requiredFirst'},
  },
} satisfies Meta<React.ComponentProps<typeof ChartCard>>
export default meta

export const RangeSelector: StoryObj<ChartCardProps> = {
  args: {
    size: 'medium',
    border: true,
    padding: 'normal',
    visibleControls: true,
  },
  render: (args: ChartCardProps) => (
    <>
      <p>
        ℹ️ This story is best{' '}
        <a href="iframe.html?id=recipes-chartcard-props--range-selector&viewMode=story">
          viewed outside of the Storybook frame
        </a>
        ; otherwise, Storybook blocks expected query param changes.
      </p>
      <DateProvider>
        <Box
          sx={{
            display: 'flex',
            justifyContent: 'flex-end',
            mb: 3,
          }}
        >
          <PeriodMenu />
        </Box>
        <ChartWithRangeSelector {...args} />
      </DateProvider>
    </>
  ),
  play: async ({canvasElement, step}) => {
    const canvas = within(canvasElement)

    // make sure the charts have fully loaded
    expect(await canvas.queryAllByRole('application').length).toBe(1)

    await step('assert that the table only shows data for the selected time range', async () => {
      const user = await userEvent.setup()
      const periodMenu = await canvas.findByRole('button', {name: 'Period: All'})
      await user.click(periodMenu)

      const lastMonthItem = await canvas.findByRole('menuitem', {name: 'Last month'})
      await user.click(lastMonthItem)
      await user.click(await canvas.findByRole('button', {name: 'Chart options'}))
      await user.click(await canvas.findByRole('menuitem', {name: 'View as table'}))

      const rows = await canvas.queryAllByRole('row')

      // The "Last month" date changes depending on when the test runs because the data shown
      // is generated based on today as an end date.
      // Even if we change the demo data to use fixed dates, PeriodMenu's `getDateMonthsAgo` always grabs a date
      // from X months prior to _today_.
      // To avoid a significant refactor in our demo, we will make test assertions within a range.
      await expect(rows.length).toBeLessThanOrEqual(35)
      await expect(rows.length).toBeGreaterThanOrEqual(25)
    })
  },
}

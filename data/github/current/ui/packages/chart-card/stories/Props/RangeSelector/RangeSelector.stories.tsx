import type {Meta} from '@storybook/react'
import {Box} from '@primer/react'
import {ChartCard, type ChartCardProps} from '../../../ChartCard'
import {ChartWithRangeSelector} from './ChartWithRangeSelector'
import {PeriodMenu} from './PeriodMenu'
import {DateProvider} from './DateContext'

const meta = {
  title: 'Recipes/ChartCard/Props',
  component: ChartCard,
  parameters: {
    controls: {expanded: true, sort: 'requiredFirst'},
  },
} satisfies Meta<React.ComponentProps<typeof ChartCard>>
export default meta

export const RangeSelector = {
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
}

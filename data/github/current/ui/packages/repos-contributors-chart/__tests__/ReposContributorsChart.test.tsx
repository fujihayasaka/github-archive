import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import contributorsData from '../test-utils/small-data'
import type {RawContributor} from '../repos-contributors-chart-types'
import ReposContributorsChart, {type ReposContributorsChartProps} from '../components/ReposContributorsChart'
import {mergeWeeksFromContributors} from '../helpers/merge-weeks-from-contributors'
import {transformWeek} from '../helpers/transform-weeks'
import {computeMetricsFromWeeks} from '../helpers/compute-metrics-from-weeks'

function createChartCard() {
  const contributors = contributorsData as RawContributor[]
  const {totals, metrics} = computeMetricsFromWeeks(mergeWeeksFromContributors(contributors))

  const args: ReposContributorsChartProps = {
    weeks: contributors[contributors.length - 1]!.weeks.map(transformWeek),
    selectedMetric: 'commits',
    totals,
    metrics,
  }

  return render(<ReposContributorsChart {...args} />)
}

test('renders correct heading hierarchy', async () => {
  createChartCard()
  const headingTwoRole = screen.getByRole('heading', {level: 2, name: 'Commits over time'})
  expect(headingTwoRole).toBeInTheDocument()

  expect(screen.queryAllByRole('heading').length).toBe(1)
})

test('renders role="application"', () => {
  createChartCard()

  expect(screen.queryAllByRole('application')).toHaveLength(1)
})

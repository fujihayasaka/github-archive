import type {Meta} from '@storybook/react'
import {Wrapper} from '@github-ui/react-core/test-utils'
import ReposContributorsChart, {type ReposContributorsChartProps} from './ReposContributorsChart'
import contributorsData from '../test-utils/small-data'
import type {RawContributor} from '../repos-contributors-chart-types'
import {mergeWeeksFromContributors} from '../helpers/merge-weeks-from-contributors'
import {transformWeek} from '../helpers/transform-weeks'
import {computeMetricsFromWeeks} from '../helpers/compute-metrics-from-weeks'

const contributors = contributorsData as RawContributor[]
const {totals, metrics} = computeMetricsFromWeeks(mergeWeeksFromContributors(contributors))

interface StoryProps extends ReposContributorsChartProps {
  repos_column_charts: boolean
}

const meta = {
  title: 'Apps/Repo Contributors',
  component: ReposContributorsChart,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  args: {
    repos_column_charts: true,
  },
  argTypes: {
    selectedMetric: {
      control: 'radio',
      options: ['commits', 'additions', 'deletions'],
    },
    repos_column_charts: {control: {type: 'boolean'}},
  },
} satisfies Meta<StoryProps>

export default meta

const defaultArgs: Partial<StoryProps> = {
  weeks: contributors[contributors.length - 1]!.weeks.map(transformWeek),
  selectedMetric: 'commits',
  totals,
  metrics,
}

export const ReposContributorsChartSingleExample = {
  args: {
    ...defaultArgs,
  },
  render: ({repos_column_charts, ...args}: StoryProps) => (
    <Wrapper appPayload={{enabled_features: {repos_column_charts}}}>
      <ReposContributorsChart {...args} />
    </Wrapper>
  ),
}

export const ReposContributorsChartFullExample = {
  args: {
    ...defaultArgs,
    weeks: mergeWeeksFromContributors(contributors),
  },
  render: ({repos_column_charts, ...args}: StoryProps) => (
    <Wrapper appPayload={{enabled_features: {repos_column_charts}}}>
      <ReposContributorsChart {...args} />
    </Wrapper>
  ),
}

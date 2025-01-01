import type {Meta} from '@storybook/react'
import {AutofixStatsMetric, type AutofixStatsMetricProps} from '../AutofixStatsMetric'

const meta = {
  title: 'Apps/Security Campaigns/Autofix Stats Metric',
  component: AutofixStatsMetric,
  argTypes: {},
} satisfies Meta<typeof AutofixStatsMetric>

export default meta

const defaultArgs: Partial<AutofixStatsMetricProps> = {
  generatedCount: 210,
  appliedCount: 50,
}

export const Default = {
  args: {
    ...defaultArgs,
  },
  render: (args: AutofixStatsMetricProps) => <AutofixStatsMetric {...args} />,
}

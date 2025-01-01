import type {Meta} from '@storybook/react'
import {AutofixMetric, type AutofixMetricProps} from '../AutofixMetric'

const meta = {
  title: 'Apps/Security Campaigns/Autofix metric',
  component: AutofixMetric,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {},
} satisfies Meta<typeof AutofixMetric>

export default meta

const defaultArgs: Partial<AutofixMetricProps> = {
  count: 100,
  isLoading: false,
}

export const Loaded = {
  args: {
    ...defaultArgs,
  },
  render: (args: AutofixMetricProps) => <AutofixMetric {...args} />,
}

export const Loading = {
  args: {
    ...defaultArgs,
    isLoading: true,
  },
  render: (args: AutofixMetricProps) => <AutofixMetric {...args} />,
}

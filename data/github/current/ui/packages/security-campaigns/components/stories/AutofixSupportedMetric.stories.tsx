import type {Meta} from '@storybook/react'
import {AutofixSupportedMetric, type AutofixSupportedMetricProps} from '../AutofixSupportedMetric'

const meta = {
  title: 'Apps/Security Campaigns/Autofix supported metric',
  component: AutofixSupportedMetric,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {},
} satisfies Meta<typeof AutofixSupportedMetric>

export default meta

const defaultArgs: Partial<AutofixSupportedMetricProps> = {
  count: 100,
  isLoading: false,
}

export const Loaded = {
  args: {
    ...defaultArgs,
  },
  render: (args: AutofixSupportedMetricProps) => <AutofixSupportedMetric {...args} />,
}

export const Loading = {
  args: {
    ...defaultArgs,
    isLoading: true,
  },
  render: (args: AutofixSupportedMetricProps) => <AutofixSupportedMetric {...args} />,
}

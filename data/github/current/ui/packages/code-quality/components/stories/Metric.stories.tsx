import type {Meta} from '@storybook/react'
import {Metric, type MetricProps} from '../Metric'

const meta = {
  title: 'Apps/Code Quality/Metric',
  component: Metric,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {},
} satisfies Meta<typeof Metric>

export default meta

const defaultArgs: Partial<MetricProps> = {
  title: 'Maintainability',
  data: {
    grade: 'A',
    findingsCount: 123,
  },
}

export const GradeA = {
  args: defaultArgs,
  render: (args: MetricProps) => <Metric {...args} />,
}

export const GradeB = {
  args: {
    ...defaultArgs,
    grade: 'B',
  },
  render: (args: MetricProps) => <Metric {...args} />,
}

export const GradeC = {
  args: {
    ...defaultArgs,
    grade: 'C',
  },
  render: (args: MetricProps) => <Metric {...args} />,
}

export const GradeD = {
  args: {
    ...defaultArgs,
    grade: 'D',
  },
  render: (args: MetricProps) => <Metric {...args} />,
}

export const NoData = {
  args: {
    ...defaultArgs,
    data: undefined,
  },
  render: (args: MetricProps) => <Metric {...args} />,
}

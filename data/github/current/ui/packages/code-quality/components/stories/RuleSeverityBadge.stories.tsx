import type {Meta} from '@storybook/react'
import {RuleSeverityBadge} from '../RuleSeverityBadge'
import {RuleSeverity} from '../../types/rule-severity'

const meta = {
  title: 'Apps/Code Quality/Rule Severity Badge',
  component: RuleSeverityBadge,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {},
} satisfies Meta<typeof RuleSeverityBadge>

export default meta

export const Note = {
  render: () => <RuleSeverityBadge severity={RuleSeverity.Note} />,
}

export const Warning = {
  render: () => <RuleSeverityBadge severity={RuleSeverity.Warning} />,
}

export const Error = {
  render: () => <RuleSeverityBadge severity={RuleSeverity.Error} />,
}

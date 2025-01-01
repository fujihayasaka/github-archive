import type {Meta} from '@storybook/react'
import {Assignees} from './Assignees'
import {AssigneeVisual, type AssigneeVisualProps} from './AssigneeVisual'

const meta = {
  title: 'IssuesComponents/AssigneeVisual',
  component: Assignees,
} satisfies Meta<typeof Assignees>

export default meta

export const AssigneeVisualDefaultExample = {
  args: {
    login: 'monalisa',
    id: '1',
    avatarUrl: 'https://avatars.githubusercontent.com/u/9919',
  },
  render: (args: AssigneeVisualProps) => <AssigneeVisual {...args} />,
}

export const AssigneeVisualCopilotExample = {
  args: {
    login: 'copilot',
    id: '1',
    avatarUrl: '',
  },
  render: (args: AssigneeVisualProps) => <AssigneeVisual {...args} />,
}

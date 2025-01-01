import type {Meta} from '@storybook/react'
import {Assignees, type AssigneesProps} from './Assignees'

const meta = {
  title: 'IssuesComponents/Assignees',
  component: Assignees,
} satisfies Meta<typeof Assignees>

export default meta

const defaultArgs: Partial<AssigneesProps> = {
  assignees: [
    {
      login: 'monalisa',
      name: 'Mona Lisa',
      id: '1',
      avatarUrl: '',
      profileResourcePath: '/monalisa',
      __typename: 'User',
    },
    {
      login: 'copilot',
      name: 'Copilot',
      id: '1',
      avatarUrl: '',
      profileResourcePath: '/apps/copilot-swe-agent',
      __typename: 'Bot',
    },
  ],
}

export const AssigneesExample = {
  args: {
    ...defaultArgs,
  },
  render: (args: AssigneesProps) => <Assignees {...args} />,
}

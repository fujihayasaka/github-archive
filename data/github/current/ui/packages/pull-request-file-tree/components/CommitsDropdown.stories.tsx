import type {Meta, StoryObj} from '@storybook/react'

import {getMockCommitsDropDownPageData} from '../test-utils/mock-data'
import {CommitsDropdown, type CommitsDropdownProps} from './CommitsDropdown'

const meta = {
  title: 'Apps/React Shared/Pull Requests/CommitsDropdown',
  component: CommitsDropdown,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof CommitsDropdown>

export default meta

type Story = StoryObj<typeof CommitsDropdown>

export const Default: Story = {
  args: getMockCommitsDropDownPageData(),
  render: (args: CommitsDropdownProps) => <CommitsDropdown {...args} />,
}

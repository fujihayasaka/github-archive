import type {Meta, StoryObj} from '@storybook/react'
import {PullRequestFileTree} from './PullRequestFileTree'

const meta = {
  title: 'Pull Requests/Files Changed/PullRequestFileTree',
  component: PullRequestFileTree,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof PullRequestFileTree>

export default meta

type Story = StoryObj<typeof PullRequestFileTree>

export const Default: Story = {
  render: () => <PullRequestFileTree />,
}

import type {Meta, StoryObj} from '@storybook/react'
import type {AgentsTaskListItemProps} from './AgentsTaskListItem'
import {AgentsTaskList} from './AgentsTaskList'
import type {Pull} from '../types/pull'

const meta: Meta<typeof AgentsTaskList> = {
  title: 'Apps/Copilot Coding Agent/AgentsTaskList',
  component: AgentsTaskList,
}

export default meta
type Story = StoryObj<typeof meta>

const pr: Pull = {
  id: 1,
  title: 'ns_eclipse: Delete block in study hall',
  url: 'https://github.com/example/repo/pull/1',
  number: 3,
  repository_nwo: 'example/repo',
  state: 'open',
  reviewable_state: 'draft',
  labels: [],
  comments: 1,
  author: 'Copilot',
  created_at: '2023-10-01T12:00:00Z',
  updated_at: '2023-10-01T12:00:00Z',
  head_sha: 'abc123',
}

const items: AgentsTaskListItemProps[] = [
  {
    merged: false,
    revisionCount: 2,
    pullRequest: pr,
    state: 'in_progress',
    lastSessionStartDate: '2023-10-01T12:00:00Z',
  },
  {
    merged: false,
    revisionCount: 1,
    pullRequest: {
      ...pr,
      title: 'ns_veil: Add new alien spawn location',
    },
    lastSessionStartDate: '2023-10-01T12:00:00Z',
    state: 'completed',
  },
  {
    merged: true,
    revisionCount: 1,
    pullRequest: {
      ...pr,
      title: 'Add konami code easter egg to main menu',
    },
    lastSessionStartDate: '2023-10-01T12:00:00Z',
    state: 'completed',
  },
]

export const Default: Story = {
  name: 'Default',
  args: {
    items,
  },
}

export const Merged: Story = {
  name: 'Merged',
  args: {
    items,
  },
}

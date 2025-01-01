import type {Meta, StoryObj} from '@storybook/react'
import {PullRequestsList} from './PullRequestsList'
import {mockDashboardPullRequests} from '../test-helpers'
import {http, HttpResponse} from 'msw'
import {storyWrapper} from '@github-ui/react-core/test-utils'

/**
 * The PullRequestsList component displays a list of pull requests for the dashboard.
 */
const meta = {
  title: 'Dashboard/PullRequestsList',
  component: PullRequestsList,
  parameters: {
    layout: 'padded',
  },
  tags: ['autodocs'],
  decorators: [storyWrapper()],
} satisfies Meta<typeof PullRequestsList>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {
  args: {
    userDisplayLogin: 'monalisa',
  },
  parameters: {
    msw: {
      handlers: [
        http.get('/pulls', () => {
          return HttpResponse.json({data: mockDashboardPullRequests})
        }),
      ],
    },
  },
}

export const Empty: Story = {
  args: {
    userDisplayLogin: 'monalisa',
  },
  parameters: {
    msw: {
      handlers: [
        http.get('/pulls', () => {
          return HttpResponse.json({data: []})
        }),
      ],
    },
  },
}

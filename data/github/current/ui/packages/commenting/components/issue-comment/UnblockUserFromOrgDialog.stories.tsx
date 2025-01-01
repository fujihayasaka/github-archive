import type {Meta, StoryObj} from '@storybook/react'
import {RelayEnvironmentProvider} from 'react-relay'
import {createMockEnvironment} from 'relay-test-utils'

import {UnblockUserFromOrgDialog} from './UnblockUserFromOrgDialog'

// Create a mock Relay environment
const mockEnvironment = createMockEnvironment()

// Relay environment provider wrapper
const withRelayEnvironment = (Story: React.ComponentType) => (
  <RelayEnvironmentProvider environment={mockEnvironment}>
    <Story />
  </RelayEnvironmentProvider>
)

const meta = {
  title: 'Commenting/UnblockUserFromOrgDialog',
  component: UnblockUserFromOrgDialog,
  parameters: {
    layout: 'centered',
    docs: {
      description: {
        component: 'A dialog to confirm unblocking a user from an organization.',
      },
    },
  },
  tags: ['autodocs'],
  argTypes: {
    onClose: {action: 'onClose'},
  },
  decorators: [withRelayEnvironment],
} satisfies Meta<typeof UnblockUserFromOrgDialog>

export default meta
type Story = StoryObj<typeof meta>

// Default props for all stories
const defaultProps = {
  organization: {
    login: 'github',
    id: 'org_1',
  },
  contentAuthor: {
    login: 'octocat',
    id: 'user_1',
  },
  contentId: 'content_1',
  onClose: () => {},
}

export const Default: Story = {
  args: defaultProps,
}

export const WithLongUsername: Story = {
  args: {
    ...defaultProps,
    contentAuthor: {
      login: 'super-long-username-that-should-wrap-properly',
      id: 'user_2',
    },
  },
  parameters: {
    docs: {
      description: {
        story: 'Shows how the dialog handles long usernames while maintaining accessibility.',
      },
    },
  },
}

export const WithLongOrgName: Story = {
  args: {
    ...defaultProps,
    organization: {
      login: 'very-long-organization-name-for-testing-ui-overflow',
      id: 'org_2',
    },
  },
  parameters: {
    docs: {
      description: {
        story: 'Shows how the dialog handles long organization names while maintaining readability.',
      },
    },
  },
}

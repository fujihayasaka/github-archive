import {noop} from '@github-ui/noop'
import type {Meta, StoryObj} from '@storybook/react'
import {RelayEnvironmentProvider} from 'react-relay'
import {createMockEnvironment} from 'relay-test-utils'

import {BlockUserFromOrgDialog} from './BlockUserFromOrgDialog'

// Create a mock Relay environment
const mockEnvironment = createMockEnvironment()

// Relay environment decorator
const withRelayEnvironment = (Story: React.ComponentType) => (
  <RelayEnvironmentProvider environment={mockEnvironment}>
    <Story />
  </RelayEnvironmentProvider>
)

const meta = {
  title: 'Commenting/BlockUserFromOrgDialog',
  component: BlockUserFromOrgDialog,
  parameters: {
    controls: {expanded: true},
    layout: 'centered',
  },
  tags: ['autodocs'],
  argTypes: {
    onClose: {action: 'onClose'},
  },
  decorators: [withRelayEnvironment],
} satisfies Meta<typeof BlockUserFromOrgDialog>

export default meta
type Story = StoryObj<typeof meta>

// Mock data for stories
const defaultProps = {
  organization: {
    login: 'github',
    id: 'org_1',
  },
  contentId: 'content_1',
  contentAuthor: {
    login: 'octocat',
    id: 'user_1',
  },
  contentUrl: 'https://github.com/github/repo/issues/1#issuecomment-1',
  onClose: noop,
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
}

export const WithLongOrgName: Story = {
  args: {
    ...defaultProps,
    organization: {
      login: 'very-long-organization-name-for-testing-ui-overflow',
      id: 'org_2',
    },
  },
}

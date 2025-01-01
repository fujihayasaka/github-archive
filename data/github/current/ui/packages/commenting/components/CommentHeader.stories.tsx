import {noop} from '@github-ui/noop'
import {shouldInteractionPlay} from '@github-ui/storybook'
import type {Meta, StoryObj} from '@storybook/react'
import {userEvent, within} from '@storybook/test'
import {RelayEnvironmentProvider} from 'react-relay'
import type {FragmentRefs} from 'relay-runtime'
import {createMockEnvironment} from 'relay-test-utils'
import type {MockResolvers} from 'relay-test-utils/lib/RelayMockPayloadGenerator'

import type {CommentAuthorAssociation} from './CommentActions.stories'
import {CommentHeader} from './CommentHeader'

// Create a mock Relay environment
const mockEnvironment = createMockEnvironment()

// Decorator to provide Relay environment
const withRelayEnvironment = (Story: React.ComponentType) => (
  <RelayEnvironmentProvider environment={mockEnvironment}>
    <Story />
  </RelayEnvironmentProvider>
)

const meta = {
  title: 'Commenting/CommentHeader',
  component: CommentHeader,
  parameters: {
    controls: {expanded: true},
    relayEnvironment: {
      mockResolvers: {
        CommentEdge: () => ({
          node: {
            __typename: 'IssueComment',
            createdAt: '2023-01-01T00:00:00Z',
            lastEditedAt: null,
            isMinimized: false,
            body: 'Hello world',
            editor: null,
          },
        }),
      } as MockResolvers,
    },
  },
  tags: ['autodocs'],
  decorators: [withRelayEnvironment],
} satisfies Meta<typeof CommentHeader>
export default meta

// Mock the fragment spreads properly
type Story = StoryObj<typeof meta>

// Mock the fragment spreads properly
const defaultComment = {
  id: '1',
  body: 'Hello world',
  authorAssociation: 'MEMBER' as CommentAuthorAssociation,
  createdAt: '2023-01-01T00:00:00Z',
  url: 'https://github.com/octocat/Hello-World/issues/1#issuecomment-1',
  author: {
    login: 'octocat',
    id: '123',
  },
  isHidden: false,
  referenceText: '',
  minimizedReason: null,
  repository: {
    owner: {id: '123', login: 'octocat', url: 'https://github.com/octocat'},
    name: 'Hello-World',
    id: '',
    isPrivate: false,
  },
  viewerCanDelete: true,
  viewerCanMinimize: true,
  viewerCanSeeMinimizeButton: true,
  viewerCanSeeUnminimizeButton: true,
  viewerCanUpdate: true,
  viewerCanReport: false,
  viewerCanReportToMaintainer: false,
  viewerCanBlockFromOrg: false,
  viewerCanUnblockFromOrg: false,
  // Properly structured fragment spreads
  ' $fragmentSpreads': {} as FragmentRefs<'MarkdownEditHistoryViewer_comment' | 'MarkdownLastEditedBy'>,
  // Adding data that the fragments expect
  lastEditedAt: null,
  editor: null,
}

export const Default: Story = {
  args: {
    comment: defaultComment,
    commentAuthorLogin: 'octocat',
    avatarUrl: 'https://avatars.githubusercontent.com/u/4696224?v=4',
    editComment: noop,
    onReplySelect: noop,
    isMinimized: false,
    navigate: noop,
    hideComment: noop,
    unhideComment: noop,
    deleteComment: noop,
    commentSubjectType: 'issue',
    // Use lazyFetchEditHistory to avoid needing real fragment data
    lazyFetchEditHistory: true,
  },
}

export const WithMenuOpen: Story = {
  args: {
    ...Default.args,
  },
  play: async ({canvasElement, step}) => {
    // Don't run interactions if user has reduced motion enabled
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)

    await step('Open the comment actions menu', async () => {
      const menuButton = canvas.getByRole('button', {name: /Comment actions for comment/i})
      await userEvent.click(menuButton)
    })
  },
}

export const WithUserAvatar: Story = {
  args: {
    ...Default.args,
    userAvatar: (
      <img src="https://avatars.githubusercontent.com/u/4696224?v=4" alt="User avatar" width={40} height={40} />
    ),
  },
}

export const WithAdditionalMessage: Story = {
  args: {
    ...Default.args,
    additionalHeaderMessage: <span>Added 2 commits</span>,
  },
}

export const AsReply: Story = {
  args: {
    ...Default.args,
    isReply: true,
    forceInlineAvatar: true,
  },
}

export const WithCustomHeading: Story = {
  args: {
    ...Default.args,
    headingProps: {
      as: 'h2',
    },
  },
}

export const HiddenActions: Story = {
  args: {
    ...Default.args,
    hideActions: true,
  },
}

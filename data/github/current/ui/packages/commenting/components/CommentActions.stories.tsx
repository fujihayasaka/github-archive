import {noop} from '@github-ui/noop'
import {shouldInteractionPlay} from '@github-ui/storybook'
import type {Meta, StoryObj} from '@storybook/react'
import {userEvent, within} from '@storybook/test'

import {CommentActions} from './CommentActions'

export type CommentAuthorAssociation =
  | 'COLLABORATOR'
  | 'CONTRIBUTOR'
  | 'FIRST_TIME_CONTRIBUTOR'
  | 'FIRST_TIMER'
  | 'MANNEQUIN'
  | 'MEMBER'
  | 'NONE'
  | 'OWNER'

const meta = {
  title: 'Commenting/CommentActions',
  component: CommentActions,
  parameters: {
    controls: {
      expanded: true,
    },
  },
} satisfies Meta<typeof CommentActions>

export default meta
type Story = StoryObj<typeof meta>
const defaultComment = {
  authorAssociation: 'CONTRIBUTOR' as CommentAuthorAssociation,
  body: 'This is a test comment',
  id: 'comment_1',
  createdAt: '2025-03-03T12:00:00Z',
  isHidden: false,
  referenceText: 'Test Issue #1',
  minimizedReason: null,
  repository: {
    id: 'repo_1',
    isPrivate: false,
    name: 'test-repo',
    owner: {
      id: 'owner_1',
      login: 'monalisa',
      url: 'https://github.com/monalisa',
    },
  },
  url: 'https://github.com/monalisa/test-repo/issues/1#issuecomment-1',
  viewerCanDelete: true,
  viewerCanMinimize: true,
  viewerCanSeeMinimizeButton: true,
  viewerCanSeeUnminimizeButton: true,
  viewerCanUpdate: true,
  viewerCanReport: true,
  viewerCanReportToMaintainer: false,
  viewerCanBlockFromOrg: false,
  viewerCanUnblockFromOrg: false,
  author: {
    id: 'user_1',
    login: 'octocat',
  },
}

export const Default: Story = {
  args: {
    comment: defaultComment,
    commentAuthorLogin: 'octocat',
    editComment: noop,
    onReplySelect: noop,
    isMinimized: false,
    navigate: noop,
    hideComment: noop,
    unhideComment: noop,
    deleteComment: noop,
  },
}

export const Minimized: Story = {
  args: {
    ...Default.args,
    isMinimized: true,
    comment: {
      ...defaultComment,
      isHidden: true,
      minimizedReason: 'off-topic',
    },
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
      const menuButton = canvas.getByRole('button', {name: /comment actions/i})
      await userEvent.click(menuButton)
    })
  },
}

export const WithReportingOptions: Story = {
  args: {
    ...Default.args,
    comment: {
      ...defaultComment,
      viewerCanReport: true,
      viewerCanReportToMaintainer: true,
    },
  },
}

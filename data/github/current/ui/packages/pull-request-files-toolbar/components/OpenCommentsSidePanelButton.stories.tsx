import type {Meta, StoryObj} from '@storybook/react'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {buildComment} from '@github-ui/conversations/test-utils'
import {relayDecorator} from '@github-ui/relay-test-utils/storybook'

import {buildThreadPreview} from '../test-utils/mock-data'
import {OpenCommentsSidePanelButton} from './OpenCommentsSidePanelButton'

const comment = buildComment({
  bodyHTML: 'thread preview text',
})

const meta = {
  title: 'PullRequests/FilesToolbar/OpenCommentsSidePanelButton',
  component: OpenCommentsSidePanelButton,
  decorators: [storyWrapper({appPayload: {helpUrl: ''}}), relayDecorator],
  args: {
    repositoryId: '123',
    pullRequestId: '456',
    threadPreviews: [
      buildThreadPreview({
        firstComment: comment,
        threadPreviewComments: [comment],
      }),
    ],
  },
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    // Needed for reaction viewer. Should be removed once the reaction viewer no longer needs relay
    relay: {
      queries: {},
    },
  },
} satisfies Meta<typeof OpenCommentsSidePanelButton>

export default meta

type Story = StoryObj<typeof OpenCommentsSidePanelButton>

export const Default: Story = {}

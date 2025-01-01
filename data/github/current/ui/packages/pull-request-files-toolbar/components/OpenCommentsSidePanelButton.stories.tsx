import type {Meta, StoryObj} from '@storybook/react'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {buildComment} from '@github-ui/conversations/test-utils'
import {relayDecorator} from '@github-ui/relay-test-utils/storybook'

import {buildThreadPreview, getPullRequestFilesToolbarMockData} from '../test-utils/mock-data'
import {OpenCommentsSidePanelButton} from './OpenCommentsSidePanelButton'
import {http, HttpResponse} from 'msw'

const comment = buildComment({
  bodyHTML: 'Comment 1 text',
})

const meta = {
  title: 'Pull Requests/FilesToolbar/OpenCommentsSidePanelButton',
  component: OpenCommentsSidePanelButton,
  decorators: [storyWrapper({appPayload: {helpUrl: ''}}), relayDecorator],
  parameters: {
    parameters: {
      controls: {disable: true, exclude: /.*/g}, // Hide controls, since this story should already be using the correct values
    },
    msw: {
      handlers: [
        http.get(`/_graphql`, () => {
          return HttpResponse.json({data: {}})
        }),
      ],
    },
    // Needed for reaction viewer. Should be removed once the reaction viewer no longer needs relay
    relay: {
      queries: {},
    },
  },
} satisfies Meta<typeof OpenCommentsSidePanelButton>

export default meta

type Story = StoryObj<typeof OpenCommentsSidePanelButton>

export const Default: Story = {
  render: () => {
    const {pullRequest} = getPullRequestFilesToolbarMockData()
    return (
      <OpenCommentsSidePanelButton
        pullRequest={pullRequest}
        repositoryId={pullRequest.repository.id}
        threadPreviews={[
          buildThreadPreview({
            firstComment: comment,
            threadPreviewComments: [comment],
          }),
        ]}
      />
    )
  },
}

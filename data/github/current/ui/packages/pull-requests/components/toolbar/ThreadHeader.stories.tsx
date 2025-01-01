import type {Meta, StoryObj} from '@storybook/react'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {buildComment, mockCommentingImplementation} from '@github-ui/conversations/test-utils'

import {buildThreadPreview} from '../../test-utils/files-changed/toolbar-mock-data'
import {ThreadHeader} from './ThreadHeader'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'

const comment = buildComment({
  bodyHTML: 'thread preview text',
})

const meta = {
  title: 'Pull Requests/FilesToolbar/ThreadHeader',
  component: ThreadHeader,
  decorators: [
    storyWrapper({appPayload: {helpUrl: ''}}),
    Story => {
      return (
        <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
          <Story />
        </PageDataContextProvider>
      )
    },
  ],
  args: {
    commentingImplementation: mockCommentingImplementation,
    isCollapsed: false,
    onNavigateToDiffComment: () => {},
    onToggleCollapsed: () => {},
    thread: buildThreadPreview({
      firstComment: comment,
      threadPreviewComments: [comment],
    }),
  },
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof ThreadHeader>

export default meta

type Story = StoryObj<typeof ThreadHeader>

export const Default: Story = {}

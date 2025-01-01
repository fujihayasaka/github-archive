import type {Meta, StoryObj} from '@storybook/react'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {buildComment, mockCommentingImplementation} from '@github-ui/conversations/test-utils'
import {relayDecorator} from '@github-ui/relay-test-utils/storybook'

import {getFilesRoutePayload} from '../../test-utils/files-changed/files-mock-data'
import {buildThreadPreview} from '../../test-utils/files-changed/toolbar-mock-data'
import {CommentsSidePanel} from './CommentsSidePanel'
import {http, HttpResponse} from 'msw'
import {noop} from '@github-ui/noop'
import {userEvent, within, expect} from '@storybook/test'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'

const monalisaComment = buildComment({
  author: {
    avatarUrl: '',
    id: '',
    login: 'monalisa',
    url: '',
  },
  bodyHTML: 'abc',
  body: 'abc',
})

const hubotComment = buildComment({
  author: {
    avatarUrl: '',
    id: '',
    login: 'hubot',
    url: '',
  },
  bodyHTML: 'jkl',
  body: 'jkl',
})

const meta = {
  title: 'Pull Requests/FilesToolbar/CommentsSidePanel',
  component: CommentsSidePanel,
  decorators: [
    storyWrapper({appPayload: {helpUrl: ''}}),
    relayDecorator,
    Story => {
      return (
        <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
          <Story />
        </PageDataContextProvider>
      )
    },
  ],
  parameters: {
    a11y: {
      test: 'todo',
    },
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
} satisfies Meta<typeof CommentsSidePanel>

export default meta

type Story = StoryObj<typeof CommentsSidePanel>

export const Default: Story = {
  render: () => {
    return (
      <CommentsSidePanel
        commentBoxConfig={mockCommentingImplementation.commentBoxConfig}
        isOpen
        threadPreviews={[
          buildThreadPreview({
            firstComment: monalisaComment,
            threadPreviewComments: [monalisaComment],
          }),
        ]}
        toggleSidesheetRef={{current: null}}
        onClose={noop}
        pageLimits={getFilesRoutePayload().pageLimits}
        pullRequestId="123"
        repositoryId="456"
      />
    )
  },
}

export const Zero_Comments_State_Test: Story = {
  render: () => (
    <CommentsSidePanel
      commentBoxConfig={mockCommentingImplementation.commentBoxConfig}
      isOpen
      threadPreviews={[]}
      toggleSidesheetRef={{current: null}}
      onClose={noop}
      pageLimits={getFilesRoutePayload().pageLimits}
      pullRequestId="123"
      repositoryId="456"
    />
  ),
  play: async ({canvasElement}) => {
    const canvas = within(canvasElement)
    await canvas.findByText('No comments on changes yet')
    canvas.getByText('Comments will show up here as soon as there are some.')
  },
}

export const Text_Filter_Test: Story = {
  render: () => {
    const threadPreviews = [
      buildThreadPreview({
        firstComment: monalisaComment,
        threadPreviewComments: [monalisaComment],
        path: 'path/to/file1',
      }),
      buildThreadPreview({
        firstComment: hubotComment,
        threadPreviewComments: [hubotComment],
        path: 'path/to/file2',
      }),
    ]

    return (
      <CommentsSidePanel
        commentBoxConfig={mockCommentingImplementation.commentBoxConfig}
        isOpen
        threadPreviews={threadPreviews}
        toggleSidesheetRef={{current: null}}
        onClose={noop}
        pageLimits={getFilesRoutePayload().pageLimits}
        pullRequestId="123"
        repositoryId="456"
      />
    )
  },
  play: async ({canvasElement, step}) => {
    const canvas = within(canvasElement)
    let filterInput: HTMLElement

    const clearFilterCheck = async () => {
      await userEvent.clear(filterInput)
      await canvas.findByText(monalisaComment.bodyHTML)
      canvas.getByText(hubotComment.bodyHTML)
    }

    step('renders full list pre-filter', () => {
      canvas.getByText(monalisaComment.bodyHTML)
      canvas.getByText(hubotComment.bodyHTML)
    })

    await step('filters text by matching body of first comment', async () => {
      filterInput = await canvas.findByPlaceholderText('Filter comments')
      await userEvent.type(filterInput, 'abc')
      await canvas.findByText(monalisaComment.bodyHTML)
      await canvas.findByText(/1 comment/i)
      expect(canvas.queryByText(hubotComment.bodyHTML)).not.toBeInTheDocument()
    })

    await step('clear filter and ensure it renders full list again', clearFilterCheck)

    await step('filters text by matching path of second comment', async () => {
      await userEvent.type(filterInput, 'abc')
      await canvas.findByText(monalisaComment.bodyHTML)
      expect(canvas.queryByText(hubotComment.bodyHTML)).not.toBeInTheDocument()
    })

    await step('clear filter and ensure it renders full list again', clearFilterCheck)

    await step('filters text by matching author of first comment', async () => {
      await userEvent.type(filterInput, 'mona')
      canvas.getByText(monalisaComment.bodyHTML)
      expect(canvas.queryByText(hubotComment.bodyHTML)).not.toBeInTheDocument()
    })

    await step('clear filter and ensure it renders full list again', clearFilterCheck)

    await step('filter with no matches shows zero state', async () => {
      await userEvent.type(filterInput, 'no matches')
      await canvas.findByText('No comments match the current filter')
      canvas.getByText('Comments will show up here as soon as there are some.')
      expect(canvas.queryByText(monalisaComment.bodyHTML)).not.toBeInTheDocument()
      expect(canvas.queryByText(hubotComment.bodyHTML)).not.toBeInTheDocument()
    })
  },
}

export const Resolved_Filter_Test: Story = {
  render: () => {
    const threadPreviews = [
      buildThreadPreview({
        firstComment: monalisaComment,
        threadPreviewComments: [monalisaComment],
        path: 'path/to/file1',
        isResolved: true,
      }),
      buildThreadPreview({
        firstComment: hubotComment,
        threadPreviewComments: [hubotComment],
        path: 'path/to/file2',
        isResolved: false,
      }),
    ]

    return (
      <CommentsSidePanel
        commentBoxConfig={mockCommentingImplementation.commentBoxConfig}
        isOpen
        threadPreviews={threadPreviews}
        toggleSidesheetRef={{current: null}}
        onClose={noop}
        pageLimits={getFilesRoutePayload().pageLimits}
        pullRequestId="123"
        repositoryId="456"
      />
    )
  },
  play: async ({canvasElement, step}) => {
    const canvas = within(canvasElement)
    let filterOptionsMenu: HTMLElement

    step('renders full list pre-filter', () => {
      canvas.getByText(monalisaComment.bodyHTML)
      canvas.getByText(hubotComment.bodyHTML)
    })

    await step('filter by resolved', async () => {
      filterOptionsMenu = await canvas.findByLabelText('Additional comment filters')
      await userEvent.click(filterOptionsMenu)
      const filterResolvedToggle = await canvas.findByLabelText('Show resolved comments')
      await userEvent.click(filterResolvedToggle)

      await canvas.findByText(hubotComment.bodyHTML)
      expect(canvas.queryByText(monalisaComment.bodyHTML)).not.toBeInTheDocument()
    })

    await step('remove resolved filter', async () => {
      await userEvent.click(filterOptionsMenu)
      const filterResolvedToggle = await canvas.findByLabelText('Show resolved comments')
      await userEvent.click(filterResolvedToggle)
      canvas.getByText(monalisaComment.bodyHTML)
      canvas.getByText(hubotComment.bodyHTML)
    })
  },
}

export const Outdated_Filter_Test: Story = {
  render: () => {
    const threadPreviews = [
      buildThreadPreview({
        firstComment: monalisaComment,
        threadPreviewComments: [monalisaComment],
        path: 'path/to/file1',
        isOutdated: true,
      }),
      buildThreadPreview({
        firstComment: hubotComment,
        threadPreviewComments: [hubotComment],
        path: 'path/to/file2',
        isOutdated: false,
      }),
    ]

    return (
      <CommentsSidePanel
        commentBoxConfig={mockCommentingImplementation.commentBoxConfig}
        isOpen
        threadPreviews={threadPreviews}
        toggleSidesheetRef={{current: null}}
        onClose={noop}
        pageLimits={getFilesRoutePayload().pageLimits}
        pullRequestId="123"
        repositoryId="456"
      />
    )
  },
  play: async ({canvasElement, step}) => {
    const canvas = within(canvasElement)
    let filterOptionsMenu: HTMLElement

    step('renders full list pre-filter', () => {
      canvas.getByText(monalisaComment.bodyHTML)
      canvas.getByText(hubotComment.bodyHTML)
    })

    await step('filter by outdated', async () => {
      filterOptionsMenu = await canvas.findByLabelText('Additional comment filters')
      await userEvent.click(filterOptionsMenu)
      const filterResolvedToggle = await canvas.findByLabelText('Show outdated comments')
      await userEvent.click(filterResolvedToggle)

      await canvas.findByText(hubotComment.bodyHTML)
      expect(canvas.queryByText(monalisaComment.bodyHTML)).not.toBeInTheDocument()
    })

    await step('remove outdated filter', async () => {
      await userEvent.click(filterOptionsMenu)
      const filterResolvedToggle = await canvas.findByLabelText('Show outdated comments')
      await userEvent.click(filterResolvedToggle)
      canvas.getByText(monalisaComment.bodyHTML)
      canvas.getByText(hubotComment.bodyHTML)
    })
  },
}

export const Author_Filter_Test: Story = {
  render: () => {
    const threadPreviews = [
      buildThreadPreview({
        firstComment: monalisaComment,
        threadPreviewComments: [monalisaComment],
        path: 'path/to/file1',
      }),
      buildThreadPreview({
        firstComment: hubotComment,
        threadPreviewComments: [hubotComment],
        path: 'path/to/file2',
      }),
    ]

    return (
      <CommentsSidePanel
        commentBoxConfig={mockCommentingImplementation.commentBoxConfig}
        isOpen
        threadPreviews={threadPreviews}
        toggleSidesheetRef={{current: null}}
        onClose={noop}
        pageLimits={getFilesRoutePayload().pageLimits}
        pullRequestId="123"
        repositoryId="456"
      />
    )
  },
  play: async ({canvasElement, step}) => {
    const canvas = within(canvasElement)
    let filterOptionsMenu: HTMLElement

    step('renders full list pre-filter', () => {
      canvas.getByText(monalisaComment.bodyHTML)
      canvas.getByText(hubotComment.bodyHTML)
    })

    await step('filter by author', async () => {
      filterOptionsMenu = await canvas.findByLabelText('Additional comment filters')
      await userEvent.click(filterOptionsMenu)
      const monalisaFilter = await canvas.findByLabelText('monalisa')
      await userEvent.click(monalisaFilter)

      await canvas.findByText(monalisaComment.bodyHTML)
      expect(canvas.queryByText(hubotComment.bodyHTML)).not.toBeInTheDocument()
    })

    await step('clicking on another author filter', async () => {
      filterOptionsMenu = await canvas.findByLabelText('Additional comment filters')
      await userEvent.click(filterOptionsMenu)
      const hubotFilter = await canvas.findByLabelText('hubot')
      await userEvent.click(hubotFilter)
      await canvas.findByText(hubotComment.bodyHTML)
      expect(canvas.queryByText(monalisaComment.bodyHTML)).not.toBeInTheDocument()
    })

    await step('remove author filter', async () => {
      await userEvent.click(filterOptionsMenu)
      const hubotFilter = await canvas.findByLabelText('hubot')
      await userEvent.click(hubotFilter)
      canvas.getByText(monalisaComment.bodyHTML)
      canvas.getByText(hubotComment.bodyHTML)
    })
  },
}

export const WarningLimitBanner: Story = {
  render: () => {
    const threadPreviews = [
      buildThreadPreview({
        firstComment: monalisaComment,
        threadPreviewComments: [monalisaComment],
        path: 'path/to/file1',
      }),
      buildThreadPreview({
        firstComment: hubotComment,
        threadPreviewComments: [hubotComment],
        path: 'path/to/file2',
      }),
    ]

    return (
      <CommentsSidePanel
        isOpen
        threadPreviews={threadPreviews}
        toggleSidesheetRef={{current: null}}
        onClose={noop}
        commentBoxConfig={mockCommentingImplementation.commentBoxConfig}
        pageLimits={{
          annotationsLimit: 100,
          annotationsLimitExceeded: false,
          filesLimit: 300,
          filesLimitExceeded: false,
          reviewThreadsLimit: 100,
          reviewThreadsLimitExceeded: true,
        }}
        pullRequestId="123"
        repositoryId="456"
      />
    )
  },
  play: async ({canvasElement, step}) => {
    const canvas = within(canvasElement)

    step('renders warning banner', () => {
      canvas.getByText('Only the first 100 threads are currently being shown.')
    })
  },
}

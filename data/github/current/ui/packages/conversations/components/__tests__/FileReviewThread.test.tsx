import {AnalyticsProvider} from '@github-ui/analytics-provider'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import type {Thread} from '../../conversations'
import {buildComment, buildReviewThread, mockCommentingImplementation} from '../../test-utils/query-data'
import {FileReviewThread} from '../FileReviewThread'

jest.mock('@github-ui/reaction-viewer/ReactionViewerRelay', () => ({
  ReactionViewerRelay: () => null,
}))

function TestComponent({thread}: {thread: Thread}) {
  const inlineReviewThreadCommentingImplementation = {
    ...mockCommentingImplementation,
    fetchThread: () => Promise.resolve(thread),
  }

  return (
    <AnalyticsProvider appName="test-app" category="test-category" metadata={{}}>
      <FileReviewThread
        commentingImplementation={inlineReviewThreadCommentingImplementation}
        filePath="README.md"
        thread={thread}
        repositoryId="test-id"
        subjectId="test-id"
      />
    </AnalyticsProvider>
  )
}

describe('FileReviewThread', () => {
  it('renders the thread and its comments and actions', async () => {
    const comment1 = buildComment({bodyHTML: 'test comment 1'})
    const comment2 = buildComment({bodyHTML: 'test comment 2'})
    const thread = buildReviewThread({
      comments: [comment1, comment2],
      isResolved: false,
      viewerCanReply: true,
    })

    render(<TestComponent thread={thread} />)

    // Wait for the thread to be loaded
    await screen.findByText('test comment 1')

    expect(screen.getByText('test comment 1')).toBeInTheDocument()
    expect(screen.getByText('test comment 2')).toBeInTheDocument()

    // Actions
    expect(screen.getByText('Collapse comment')).toBeInTheDocument()
    expect(screen.getByText('Resolve conversation')).toBeInTheDocument()
    const moreActions = screen.getAllByTestId('comment-header-hamburger')[0]
    expect(moreActions).toBeInTheDocument()
    expect(screen.getByText('Write a reply')).toBeInTheDocument()
  })

  it('renders the resolve button when the thread has non-pending comments', async () => {
    const comment1 = buildComment({bodyHTML: 'test comment 1'})
    const comment2 = buildComment({bodyHTML: 'test comment 2'})
    const thread = buildReviewThread({
      comments: [comment1, comment2],
      isResolved: false,
    })

    render(<TestComponent thread={thread} />)

    // Wait for the thread to be loaded
    await screen.findByText('test comment 1')

    const resolveButton = screen.getByText('Resolve conversation')
    expect(resolveButton).toBeVisible()
  })

  it('does not render the resolve button when the thread has only pending comments', async () => {
    const comment1 = buildComment({bodyHTML: 'test comment 1', state: 'PENDING'})
    const comment2 = buildComment({bodyHTML: 'test comment 2', state: 'PENDING'})
    const thread = buildReviewThread({
      comments: [comment1, comment2],
      isResolved: false,
    })

    render(<TestComponent thread={thread} />)

    // Wait for the thread to be loaded
    await screen.findByText('test comment 1')

    const resolveButton = screen.queryByText('Resolve conversation')
    expect(resolveButton).not.toBeInTheDocument()
  })

  it('renders the resolve button when the thread has a pending comment and a non-pending comment', async () => {
    const comment1 = buildComment({bodyHTML: 'test comment 1'})
    const comment2 = buildComment({bodyHTML: 'test comment 2', state: 'PENDING'})
    const thread = buildReviewThread({
      comments: [comment1, comment2],
      isResolved: false,
    })

    render(<TestComponent thread={thread} />)

    // Wait for the thread to be loaded
    await screen.findByText('test comment 1')

    const resolveButton = screen.getByText('Resolve conversation')
    expect(resolveButton).toBeVisible()
  })
})

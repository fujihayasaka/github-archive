import {AnalyticsProvider} from '@github-ui/analytics-provider'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import type {Thread, ThreadSummary} from '../../conversations'
import {buildComment, buildReviewThread, mockCommentingImplementation} from '../../test-utils/query-data'
import {InlineReviewThread} from '../InlineReviewThread'

jest.mock('@github-ui/reaction-viewer/ReactionViewerRelay', () => ({
  ReactionViewerRelay: () => null,
}))

function TestComponent({thread}: {thread: Thread}) {
  const threadSummary: ThreadSummary = {
    ...thread,
    author: thread.commentsData?.comments[0]?.author ?? {avatarUrl: '', login: ''},
    commentCount: thread.commentsData?.comments.length ?? 0,
    isOutdated: thread.isOutdated ?? false,
  }

  const inlineReviewThreadCommentingImplementation = {
    ...mockCommentingImplementation,
    fetchThread: () => Promise.resolve(thread),
  }

  return (
    <AnalyticsProvider appName="test-app" category="test-category" metadata={{}}>
      <InlineReviewThread
        batchingEnabled={false}
        batchPending={false}
        enterDialogMode={() => {}}
        isOutdated={false}
        commentingImplementation={inlineReviewThreadCommentingImplementation}
        filePath="README.md"
        onThreadSelected={() => {}}
        threadId={thread.id}
        threads={[threadSummary]}
        repositoryId="test-id"
        subjectId="test-id"
      />
    </AnalyticsProvider>
  )
}

describe('InlineReviewThread', () => {
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

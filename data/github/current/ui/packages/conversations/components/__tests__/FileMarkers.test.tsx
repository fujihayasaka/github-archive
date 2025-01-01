import {AnalyticsProvider} from '@github-ui/analytics-provider'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import type {Thread} from '../../conversations'
import {buildComment, buildReviewThread, mockCommentingImplementation} from '../../test-utils/query-data'
import {FileMarkers} from '../FileMarkers'

jest.mock('@github-ui/reaction-viewer/ReactionViewerRelay', () => ({
  ReactionViewerRelay: () => null,
}))

function TestComponent({threads}: {threads: Thread[]}) {
  const inlineReviewThreadCommentingImplementation = {
    ...mockCommentingImplementation,
    fetchThread: (threadId: string) => Promise.resolve(threads.find(thread => thread.id === threadId)),
  }

  return (
    <AnalyticsProvider appName="test-app" category="test-category" metadata={{}}>
      <FileMarkers
        commentingImplementation={inlineReviewThreadCommentingImplementation}
        filePath="README.md"
        conversationListThreads={threads}
        repositoryId="test-id"
        subjectId="test-id"
      />
    </AnalyticsProvider>
  )
}

describe('FileMarkers', () => {
  it('renders a file level thread', async () => {
    const comment1 = buildComment({bodyHTML: 'test comment 1'})
    const comment2 = buildComment({bodyHTML: 'test comment 2'})
    const thread = buildReviewThread({
      comments: [comment1, comment2],
      isResolved: false,
    })

    render(<TestComponent threads={[thread]} />)

    // Wait for the thread to be loaded
    await screen.findByText('test comment 1')

    expect(screen.getByText('test comment 1')).toBeInTheDocument()
    expect(screen.getByText('test comment 2')).toBeInTheDocument()
  })

  it('renders multiple file level threads', async () => {
    const comment1 = buildComment({bodyHTML: 'test comment 1'})
    const comment2 = buildComment({bodyHTML: 'test comment 2'})
    const thread1 = buildReviewThread({
      comments: [comment1],
      isResolved: false,
    })
    const thread2 = buildReviewThread({
      comments: [comment2],
      isResolved: false,
    })

    render(<TestComponent threads={[thread1, thread2]} />)

    // Wait for the threads to be loaded
    await screen.findByText('test comment 1')
    await screen.findByText('test comment 2')

    expect(screen.getByText('test comment 1')).toBeInTheDocument()
    expect(screen.getByText('test comment 2')).toBeInTheDocument()
  })
})

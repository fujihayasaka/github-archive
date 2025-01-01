import {buildComment} from '@github-ui/conversations/test-utils'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {useRef, useState} from 'react'
import {RelayEnvironmentProvider} from 'react-relay'
import {createMockEnvironment} from 'relay-test-utils'

import {buildThreadPreview} from '../../test-utils/mock-data'
import {CommentsSidePanel} from '../CommentsSidePanel'
import type {ThreadPreviewsPayload} from '../../page-data/payloads/thread-previews'

interface TestComponentProps {
  pullRequestId?: string
  threadPreviews: ThreadPreviewsPayload
}

// Needed for reaction viewer. Should be removed once the reaction viewer no longer needs relay
const environment = createMockEnvironment()

function TestComponent({threadPreviews}: TestComponentProps) {
  const [, setCommentsSidePanelIsOpen] = useState(true)
  const toggleSidesheetRef = useRef<HTMLButtonElement>(null)

  const exitOverlay = () => {
    setCommentsSidePanelIsOpen(false)
  }

  return (
    <RelayEnvironmentProvider environment={environment}>
      <CommentsSidePanel
        isOpen
        threadPreviews={threadPreviews}
        toggleSidesheetRef={toggleSidesheetRef}
        onClose={exitOverlay}
        pullRequestId="123"
        repositoryId="456"
      />
    </RelayEnvironmentProvider>
  )
}

test('renders the thread preview for a thread', async () => {
  const comment1 = buildComment({
    bodyHTML: 'thread preview text',
  })

  const thread1 = buildThreadPreview({
    firstComment: comment1,
    threadPreviewComments: [comment1],
  })

  render(<TestComponent threadPreviews={[thread1]} />)

  // get thread preview
  const threadPreview = await screen.findByText('thread preview text')
  expect(threadPreview).toBeInTheDocument()
})

test('renders a thread preview for every thread', async () => {
  const comment1 = buildComment({
    bodyHTML: 'thread preview text',
  })

  const thread1 = buildThreadPreview({
    firstComment: comment1,
    threadPreviewComments: [comment1],
  })

  const comment2 = buildComment({
    bodyHTML: 'second thread preview text',
  })

  const thread2 = buildThreadPreview({
    firstComment: comment2,
    threadPreviewComments: [comment2],
  })

  const comment3 = buildComment({
    bodyHTML: 'third thread preview text',
  })

  const thread3 = buildThreadPreview({
    firstComment: comment3,
    threadPreviewComments: [comment3],
  })

  render(<TestComponent threadPreviews={[thread1, thread2, thread3]} />)

  // get thread summaries
  const threadSummary1 = await screen.findByText('thread preview text')
  expect(threadSummary1).toBeInTheDocument()

  const threadSummary2 = await screen.findByText('second thread preview text')
  expect(threadSummary2).toBeInTheDocument()

  const threadSummary3 = await screen.findByText('third thread preview text')
  expect(threadSummary3).toBeInTheDocument()
})

describe('filtering threads', () => {
  test('by text filter', async () => {
    const comment1 = buildComment({
      author: {
        avatarUrl: '',
        id: '',
        login: 'mona',
        url: '',
      },
      bodyHTML: 'abc',
      body: 'abc',
    })

    const thread1 = buildThreadPreview({
      firstComment: comment1,
      threadPreviewComments: [comment1],
      path: 'path/to/file1',
    })

    const comment2 = buildComment({
      author: {
        avatarUrl: '',
        id: '',
        login: 'lisa',
        url: '',
      },
      bodyHTML: 'jkl',
      body: 'jkl',
    })

    const thread2 = buildThreadPreview({
      firstComment: comment2,
      threadPreviewComments: [comment2],
      path: 'path/to/file2',
    })

    const {user} = render(<TestComponent threadPreviews={[thread1, thread2]} />)

    const assertBothThreadsPresent = async () => {
      expect(await screen.findByText('abc')).toBeInTheDocument()
      expect(await screen.findByText('jkl')).toBeInTheDocument()
    }

    // both threads are present
    await assertBothThreadsPresent()

    // filter to just the first comment by matching body
    const filterInput = await screen.findByPlaceholderText('Filter threads')
    await user.type(filterInput, 'abc')

    // only the first thread is present
    expect(await screen.findByText('abc')).toBeInTheDocument()
    expect(screen.queryByText('jkl')).not.toBeInTheDocument()

    await user.clear(filterInput)
    await assertBothThreadsPresent()

    // filter to just the second comment by matching path
    await user.type(filterInput, 'file2')

    // only the second thread is present
    expect(await screen.findByText('jkl')).toBeInTheDocument()
    expect(screen.queryByText('abc')).not.toBeInTheDocument()

    await user.clear(filterInput)
    await assertBothThreadsPresent()

    // filter to just the first comment by matching author
    await user.type(filterInput, 'mona')

    // only the first thread is present
    expect(await screen.findByText('abc')).toBeInTheDocument()
    expect(screen.queryByText('jkl')).not.toBeInTheDocument()

    await user.clear(filterInput)
    await assertBothThreadsPresent()

    // filter with no matches
    await user.type(filterInput, 'no matches')
    expect(screen.queryByText('abc')).not.toBeInTheDocument()
    expect(screen.queryByText('jkl')).not.toBeInTheDocument()

    // zero state is displayed
    expect(await screen.findByText('No comments match the current filter')).toBeInTheDocument()
    expect(await screen.findByText('Comments will show up here as soon as there are some.')).toBeInTheDocument()
  })

  test('by resolved state', async () => {
    const comment1 = buildComment({
      author: {
        avatarUrl: '',
        id: '',
        login: 'mona',
        url: '',
      },
      bodyHTML: 'abc',
      body: 'abc',
    })

    const thread1 = buildThreadPreview({
      firstComment: comment1,
      threadPreviewComments: [comment1],
      path: 'path/to/file1',
      isResolved: true,
    })

    const comment2 = buildComment({
      author: {
        avatarUrl: '',
        id: '',
        login: 'lisa',
        url: '',
      },
      bodyHTML: 'jkl',
      body: 'jkl',
    })

    const thread2 = buildThreadPreview({
      firstComment: comment2,
      threadPreviewComments: [comment2],
      path: 'path/to/file2',
      isResolved: false,
    })

    const {user} = render(<TestComponent threadPreviews={[thread1, thread2]} />)

    const assertBothThreadsPresent = async () => {
      expect(await screen.findByText('abc')).toBeInTheDocument()
      expect(await screen.findByText('jkl')).toBeInTheDocument()
    }

    // both threads are present
    await assertBothThreadsPresent()

    const filterOptionsMenu = await screen.findByLabelText('Additional thread filters')
    await user.click(filterOptionsMenu)
    let filterResolvedToggle = await screen.findByLabelText('Resolved threads')
    await user.click(filterResolvedToggle)

    // only the second thread is present
    expect(await screen.findByText('jkl')).toBeInTheDocument()
    expect(screen.queryByText('abc')).not.toBeInTheDocument()

    await user.click(filterOptionsMenu)
    filterResolvedToggle = await screen.findByLabelText('Resolved threads')
    await user.click(filterResolvedToggle)

    await assertBothThreadsPresent()
  })
})

test('sidesheet shows zero state when there are no threads', async () => {
  render(<TestComponent threadPreviews={[]} />)

  // zero state is displayed
  expect(await screen.findByText('No comments on changes yet')).toBeInTheDocument()
  expect(await screen.findByText('Comments will show up here as soon as there are some.')).toBeInTheDocument()
})

import {render, screen} from '@testing-library/react'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'

import DiffLineScreenReaderSummary, {buildDiffLineScreenReaderSummary} from '../DiffLineScreenReaderSummary'
import {buildComment, buildDiffLine, buildThread} from '../../test-utils/query-data'

jest.mock('@github-ui/react-core/use-app-payload')
const mockedUseAppPayload = jest.mocked(useAppPayload)

function mockFeatureFlags(enabledFeatureFlags: {[key: string]: boolean | undefined}) {
  mockedUseAppPayload.mockReturnValue({
    initial_view_content: {},
    enabled_features: enabledFeatureFlags || {},
  })
}

beforeEach(() => {
  jest.clearAllMocks()
})

describe('DiffLineSummary', () => {
  const thread1 = buildThread({
    comments: [
      buildComment({
        author: {login: 'thread1', avatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4', url: '/monalisa'},
      }),
    ],
  })
  const thread2 = buildThread({
    comments: [
      buildComment({
        author: {login: 'thread2', avatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4', url: '/monalisa'},
      }),
    ],
  })
  const thread3 = buildThread({
    comments: [
      buildComment({
        author: {login: 'thread3', avatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4', url: '/monalisa'},
      }),
    ],
  })
  const thread4 = buildThread({
    comments: [
      buildComment({
        author: {login: 'thread4', avatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4', url: '/monalisa'},
      }),
    ],
  })

  describe('on the original line', () => {
    test('when the original (left line) and modified (right line) have no conversations, it is empty', () => {
      const leftLine = buildDiffLine({threads: []})
      const rightLine = buildDiffLine({threads: []})
      const summary = buildDiffLineScreenReaderSummary(leftLine, rightLine, 'LEFT')

      render(<DiffLineScreenReaderSummary summary={summary ?? ''} />)
      expect(screen.queryByTestId('pr-diffline-summary')).not.toBeInTheDocument()
    })

    test('when the original (left line) and modified (right line) both have conversations, it announces both have conversations', () => {
      const leftLine = buildDiffLine({threads: [thread1, thread2]})
      const rightLine = buildDiffLine({threads: [thread3, thread4]})
      const summary = buildDiffLineScreenReaderSummary(leftLine, rightLine, 'LEFT')

      render(<DiffLineScreenReaderSummary summary={summary ?? ''} />)
      expect(screen.getByText('Has conversations. Modified line has conversations.')).toBeInTheDocument()
    })

    test('when the original (left line) and modified (right line) both have one conversation, it announces that each line has conversation', () => {
      const leftLine = buildDiffLine({threads: [thread1]})
      const rightLine = buildDiffLine({threads: [thread2]})
      const summary = buildDiffLineScreenReaderSummary(leftLine, rightLine, 'LEFT')

      render(<DiffLineScreenReaderSummary summary={summary ?? ''} />)
      expect(screen.getByText('Has a conversation. Modified line has a conversation.')).toBeInTheDocument()
    })

    test('when the original (left line) has no conversations and modified (right line) has one conversation, it announces the modified line has conversation', () => {
      const leftLine = buildDiffLine({threads: []})
      const rightLine = buildDiffLine({threads: [thread1]})
      const summary = buildDiffLineScreenReaderSummary(leftLine, rightLine, 'LEFT')

      render(<DiffLineScreenReaderSummary summary={summary ?? ''} />)
      expect(screen.getByText('Modified line has a conversation.')).toBeInTheDocument()
    })

    test('when the original (left line) has one conversation and modified (right line) has no conversations, it announces that it has conversation', () => {
      const leftLine = buildDiffLine({threads: [thread1]})
      const rightLine = buildDiffLine({threads: []})
      const summary = buildDiffLineScreenReaderSummary(leftLine, rightLine, 'LEFT')

      render(<DiffLineScreenReaderSummary summary={summary ?? ''} />)
      expect(screen.getByText('Has a conversation.')).toBeInTheDocument()
    })

    test('when the original (left line) has multiple conversations and modified (right line) has no conversations, it indicates the original line has conversations', () => {
      const leftLine = buildDiffLine({threads: [thread1, thread2]})
      const rightLine = buildDiffLine({threads: []})
      const summary = buildDiffLineScreenReaderSummary(leftLine, rightLine, 'LEFT')

      render(<DiffLineScreenReaderSummary summary={summary ?? ''} />)
      expect(screen.getByText('Has conversations.')).toBeInTheDocument()
    })

    test('when the original (left line) has no conversations and modified (right line) has multiple conversations, it indicates the modified line has conversations', () => {
      const leftLine = buildDiffLine({threads: []})
      const rightLine = buildDiffLine({threads: [thread1, thread2]})
      const summary = buildDiffLineScreenReaderSummary(leftLine, rightLine, 'LEFT')

      render(<DiffLineScreenReaderSummary summary={summary ?? ''} />)
      expect(screen.getByText('Modified line has conversations.')).toBeInTheDocument()
    })

    test('when the original (left line) has one conversation and modified (right line) has multiple conversations, it announces that each side has conversations', () => {
      const leftLine = buildDiffLine({threads: [thread1]})
      const rightLine = buildDiffLine({threads: [thread2, thread3]})
      const summary = buildDiffLineScreenReaderSummary(leftLine, rightLine, 'LEFT')

      render(<DiffLineScreenReaderSummary summary={summary ?? ''} />)
      expect(screen.getByText('Has a conversation. Modified line has conversations.')).toBeInTheDocument()
    })

    test('when the original (left line) has multiple conversations and modified (right line) has one conversation, it indicates original line has conversations and announces the author of the conversation of the modified line', () => {
      const leftLine = buildDiffLine({threads: [thread1, thread2]})
      const rightLine = buildDiffLine({threads: [thread3]})
      const summary = buildDiffLineScreenReaderSummary(leftLine, rightLine, 'LEFT')

      render(<DiffLineScreenReaderSummary summary={summary ?? ''} />)
      expect(screen.getByText('Has conversations. Modified line has a conversation.')).toBeInTheDocument()
    })
  })

  describe('on modified line', () => {
    test('when the original (left line) and modified (right line) have no conversations, it is empty', () => {
      const leftLine = buildDiffLine({threads: []})
      const rightLine = buildDiffLine({threads: []})
      const summary = buildDiffLineScreenReaderSummary(leftLine, rightLine, 'RIGHT')

      render(<DiffLineScreenReaderSummary summary={summary ?? ''} />)

      // eslint-disable-next-line testing-library/no-node-access
      const bodyChildElements = document.querySelector('body > *')?.children
      // Assert that the component returns `null` by testing that the <body> has no children elements
      expect(bodyChildElements).toHaveLength(0)
    })

    test('when the original (left line) and modified (right line) both have conversations, it announces both have conversations', () => {
      const leftLine = buildDiffLine({threads: [thread1, thread2]})
      const rightLine = buildDiffLine({threads: [thread3, thread4]})
      const summary = buildDiffLineScreenReaderSummary(leftLine, rightLine, 'RIGHT')

      render(<DiffLineScreenReaderSummary summary={summary ?? ''} />)
      expect(screen.getByText('Has conversations. Original line has conversations.')).toBeInTheDocument()
    })

    test('when the original (left line) and modified (right line) both have one conversation, it announces there is a conversation for each line', () => {
      const leftLine = buildDiffLine({threads: [thread1]})
      const rightLine = buildDiffLine({threads: [thread2]})
      const summary = buildDiffLineScreenReaderSummary(leftLine, rightLine, 'RIGHT')

      render(<DiffLineScreenReaderSummary summary={summary ?? ''} />)
      expect(screen.getByText('Has a conversation. Original line has a conversation.')).toBeInTheDocument()
    })

    test('when the original (left line) has no conversations and modified (right line) has one conversation, it announces it has a conversation', () => {
      const leftLine = buildDiffLine({threads: []})
      const rightLine = buildDiffLine({threads: [thread1]})
      const summary = buildDiffLineScreenReaderSummary(leftLine, rightLine, 'RIGHT')

      render(<DiffLineScreenReaderSummary summary={summary ?? ''} />)
      expect(screen.getByText('Has a conversation.')).toBeInTheDocument()
    })

    test('when the original (left line) has one conversation and modified (right line) has no conversations, it announces Original line has conversation', () => {
      const leftLine = buildDiffLine({threads: [thread1]})
      const rightLine = buildDiffLine({threads: []})
      const summary = buildDiffLineScreenReaderSummary(leftLine, rightLine, 'RIGHT')

      render(<DiffLineScreenReaderSummary summary={summary ?? ''} />)
      expect(screen.getByText('Original line has a conversation.')).toBeInTheDocument()
    })

    test('when the original (left line) has conversation(s) and modified (right line) has no conversations, it indicates the original line has conversations', () => {
      const leftLine = buildDiffLine({threads: [thread1, thread2]})
      const rightLine = buildDiffLine({threads: []})
      const summary = buildDiffLineScreenReaderSummary(leftLine, rightLine, 'RIGHT')

      render(<DiffLineScreenReaderSummary summary={summary ?? ''} />)
      expect(screen.getByText('Original line has conversations.')).toBeInTheDocument()
    })

    test('when the original (left line) has no conversations and modified (right line) has conversation(s), it indicates the modified line has conversations', () => {
      const leftLine = buildDiffLine({threads: []})
      const rightLine = buildDiffLine({threads: [thread1, thread2]})
      const summary = buildDiffLineScreenReaderSummary(leftLine, rightLine, 'RIGHT')

      render(<DiffLineScreenReaderSummary summary={summary ?? ''} />)
      expect(screen.getByText('Has conversations.')).toBeInTheDocument()
    })

    test('when the original (left line) has one conversation and modified (right line) has multiple conversations, it announces the original line conversation and indicates the modified line has conversations', () => {
      const leftLine = buildDiffLine({threads: [thread1]})
      const rightLine = buildDiffLine({threads: [thread2, thread3]})
      const summary = buildDiffLineScreenReaderSummary(leftLine, rightLine, 'RIGHT')

      render(<DiffLineScreenReaderSummary summary={summary ?? ''} />)
      expect(screen.getByText('Has conversations. Original line has a conversation.')).toBeInTheDocument()
    })

    test('when the original (left line) has multiple conversations and modified (right line) has one conversation, it indicates original line has conversations and announces the author of the conversation of the modified line', () => {
      const leftLine = buildDiffLine({threads: [thread1, thread2]})
      const rightLine = buildDiffLine({threads: [thread3]})
      const summary = buildDiffLineScreenReaderSummary(leftLine, rightLine, 'RIGHT')

      render(<DiffLineScreenReaderSummary summary={summary ?? ''} />)
      expect(screen.getByText('Has a conversation. Original line has conversations.')).toBeInTheDocument()
    })
  })

  test('when :diff_inline_comments Feature Flag is enabled, it adds a message to indicate the user can press enter to view the comments', () => {
    const leftLine = buildDiffLine({threads: [thread1, thread2]})
    const rightLine = buildDiffLine({threads: [thread3]})
    const summary = buildDiffLineScreenReaderSummary(leftLine, rightLine, 'RIGHT')

    mockFeatureFlags({diff_inline_comments: true})

    render(<DiffLineScreenReaderSummary summary={summary ?? ''} />)
    expect(
      screen.getByText('Has a conversation. Original line has conversations. Press Enter to view.'),
    ).toBeInTheDocument()
  })
})

import {CopilotChatProvider} from '@github-ui/copilot-chat/CopilotChatContext'
import {
  getCopilotChatProviderProps,
  getDefaultReducerState,
  getThreadMock,
} from '@github-ui/copilot-chat/test-utils/mock-data'
import type {CopilotChatThread} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {ConversationActionDialogs} from '../ConversationActions'

const mockNavigateToNewThread = jest.fn()
jest.mock('../../hooks/use-navigate-to-new-thread', () => ({
  useNavigateToNewThread: () => mockNavigateToNewThread,
}))

const mockDeleteThread = jest.fn()
jest.mock('@github-ui/copilot-chat/CopilotChatManagerContext', () => ({
  ...jest.requireActual('@github-ui/copilot-chat/CopilotChatManagerContext'),
  useChatManager: () => ({
    deleteThread: mockDeleteThread,
  }),
}))

describe('ConversationActionDialogs', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  describe('DeleteDialog', () => {
    const threads = new Map<string, CopilotChatThread>(
      [
        {...getThreadMock(), id: 'thread-1'},
        {...getThreadMock(), id: 'thread-2'},
        {...getThreadMock(), id: 'thread-3'},
      ].map(thread => [thread.id, thread]),
    )

    it('should render the dialog', () => {
      render(
        <CopilotChatProvider {...getCopilotChatProviderProps()}>
          <ConversationActionDialogs
            visibleDialog={'delete'}
            onClose={jest.fn()}
            threadName={''}
            threadId={''}
            onStartLoading={jest.fn()}
            onFinishLoading={jest.fn()}
          />
        </CopilotChatProvider>,
      )

      expect(screen.getByRole('alertdialog')).toBeInTheDocument()
      expect(screen.getByText('Delete conversation')).toBeInTheDocument()
    })

    it('should navigate to a new thread when deleting the current thread', async () => {
      const currentThread = threads.get('thread-1')!
      const listItemThread = threads.get('thread-1')!

      const {user} = render(
        <CopilotChatProvider
          {...getCopilotChatProviderProps()}
          testReducerState={{
            ...getDefaultReducerState(currentThread.id, undefined, 'immersive'),
            threads,
          }}
        >
          <ConversationActionDialogs
            visibleDialog={'delete'}
            onClose={jest.fn()}
            threadName={''}
            threadId={listItemThread.id}
            selectedThreadId={currentThread.id}
            onStartLoading={jest.fn()}
            onFinishLoading={jest.fn()}
          />
        </CopilotChatProvider>,
      )

      expect(screen.getByRole('alertdialog')).toBeInTheDocument()

      const deleteButton = screen.getByText('Delete')
      expect(deleteButton).toBeInTheDocument()

      await user.click(deleteButton)

      expect(mockNavigateToNewThread).toHaveBeenCalledWith({
        clearTopic: true,
        includeThreads: false,
      })
      expect(mockDeleteThread).toHaveBeenCalledWith(listItemThread)
    })

    it('should not navigate when deleting a different thread', async () => {
      const currentThread = threads.get('thread-1')!
      const listItemThread = threads.get('thread-2')!

      const {user} = render(
        <CopilotChatProvider
          {...getCopilotChatProviderProps()}
          testReducerState={{
            ...getDefaultReducerState(currentThread.id, undefined, 'immersive'),
            threads,
          }}
        >
          <ConversationActionDialogs
            visibleDialog={'delete'}
            onClose={jest.fn()}
            threadName={''}
            threadId={listItemThread.id}
            selectedThreadId={currentThread.id}
            onStartLoading={jest.fn()}
            onFinishLoading={jest.fn()}
          />
        </CopilotChatProvider>,
      )

      expect(screen.getByRole('alertdialog')).toBeInTheDocument()

      const deleteButton = screen.getByText('Delete')
      expect(deleteButton).toBeInTheDocument()

      await user.click(deleteButton)

      expect(mockNavigateToNewThread).not.toHaveBeenCalled()
      expect(mockDeleteThread).toHaveBeenCalledWith(listItemThread)
    })
  })
})

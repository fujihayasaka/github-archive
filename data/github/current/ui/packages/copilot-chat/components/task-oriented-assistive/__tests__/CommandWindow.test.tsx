import {render} from '@github-ui/react-core/test-utils'
import {act, screen} from '@testing-library/react'

import {getCopilotChatProviderProps, getReducerStateMock, getRepositoryMock} from '../../../test-utils/mock-data'
import type {PullRequestReference} from '../../../utils/copilot-chat-types'
import {CopilotChatProvider} from '../../../utils/CopilotChatContext'
import {CommandWindow} from '../CommandWindow'

const mockSendChatMessage = jest.fn()
const mockStopStreaming = jest.fn()
const mockClearThread = jest.fn()
const mockCloseChat = jest.fn()
const mockGetSelectedThread = jest.fn()

jest.mock('@github-ui/copilot-chat/CopilotChatManagerContext', () => ({
  ...jest.requireActual('@github-ui/copilot-chat/CopilotChatManagerContext'),
  useChatManager: () => ({
    sendChatMessage: mockSendChatMessage,
    stopStreaming: mockStopStreaming,
    clearThread: mockClearThread,
    closeChat: mockCloseChat,
    getSelectedThread: mockGetSelectedThread,
  }),
}))

describe('CommandWindow', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  it('should render the dialog', () => {
    render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        topic={getRepositoryMock()}
        testReducerState={{
          ...getReducerStateMock(),
          chatIsOpen: true,
          context: [
            {
              type: 'pull-request',
              number: 123,
            } as unknown as PullRequestReference,
          ],
        }}
      >
        <CommandWindow />
      </CopilotChatProvider>,
    )

    expect(screen.getByRole('dialog')).toBeInTheDocument()
  })

  it('should not render if the chat is not open', () => {
    render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        testReducerState={{
          ...getReducerStateMock(),
          chatIsOpen: false,
        }}
      >
        <CommandWindow />
      </CopilotChatProvider>,
    )

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('should close the dialog', () => {
    render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        topic={getRepositoryMock()}
        testReducerState={{
          ...getReducerStateMock(),
          chatIsOpen: true,
          context: [
            {
              type: 'pull-request',
              number: 123,
            } as unknown as PullRequestReference,
          ],
        }}
      >
        <CommandWindow />
      </CopilotChatProvider>,
    )

    expect(screen.getByRole('dialog')).toBeInTheDocument()
    const close = screen.getByRole('button', {name: 'Close'})
    expect(close).toBeInTheDocument()

    act(() => close?.click())
    expect(mockCloseChat).toHaveBeenCalled()
  })

  it('should submit the selected command', () => {
    render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        topic={getRepositoryMock()}
        testReducerState={{
          ...getReducerStateMock(),
          chatIsOpen: true,
          context: [
            {
              type: 'pull-request',
              number: 123,
            } as unknown as PullRequestReference,
          ],
        }}
      >
        <CommandWindow />
      </CopilotChatProvider>,
    )

    expect(screen.getByRole('dialog')).toBeInTheDocument()
    const command = screen.getByText('Proof read this pull request')
    expect(command).toBeInTheDocument()

    act(() => command?.click())
    expect(mockSendChatMessage).toHaveBeenCalled()
  })
})

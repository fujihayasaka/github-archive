import {getCopilotChatProviderProps, getDefaultReducerState} from '@github-ui/copilot-chat/test-utils/mock-data'
import type {CopilotChatMessage, GitHubAgentReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {ChatStateProvider, CopilotChatProvider} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {render} from '@github-ui/react-core/test-utils'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {screen} from '@testing-library/react'

import {ChatMessage} from '../ChatMessage'
import {ContentPreviewProvider} from '../ContentPreview/ContentPreviewContext'

// jest.mock('react-router-dom', () => ({...jest.requireActual('react-router-dom'), useLocation: jest.fn()}))
jest.mock('@github-ui/ssr-utils', () => ({
  ...jest.requireActual('@github-ui/ssr-utils'),
  // Allows safe-storage module to use local storage
  ssrSafeWindow: window,
  // Provides the current page location to useRouteThreadId
  ssrSafeLocation: {origin: 'https://github.localhost', pathname: '/copilot/c/123'},
}))

const mockedssrSafeLocation = jest.mocked(ssrSafeLocation)
function mockPageURL(path: string) {
  mockedssrSafeLocation.pathname = path
}

describe('retry button', () => {
  beforeEach(() => {
    mockPageURL('/copilot/c/thread-uuid')
  })

  it('renders when isErrorRetryable is true', async () => {
    render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="2" mode="immersive">
        <ContentPreviewProvider>
          <ChatMessage
            autoOpenPreviewPane
            isLatestMessage
            messageIndex={0}
            message={{
              id: '12',
              role: 'assistant',
              createdAt: '2020-01-01T00:00:00Z',
              threadID: '12',
              references: [],
              content: 'test',
              error: {
                type: 'agentRequest',
                message: 'Something went wrong',
                details: {
                  identifier: '',
                  type: 'agentRequest',
                  code: '500',
                  message: 'Something went wrong',
                },
                retryable: true,
                isError: true,
              },
            }}
          />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(await screen.findByTestId('retry-button')).toBeInTheDocument()
  })

  it('renders when interrupted is true', async () => {
    render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="2" mode="immersive">
        <ContentPreviewProvider>
          <ChatMessage
            autoOpenPreviewPane
            isLatestMessage
            messageIndex={0}
            message={{
              id: '12',
              role: 'assistant',
              createdAt: '2020-01-01T00:00:00Z',
              threadID: '12',
              references: [],
              content: 'test',
              interrupted: true,
            }}
          />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(await screen.findByTestId('retry-button')).toBeInTheDocument()
  })

  it('retry button renders', async () => {
    render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="2" mode="immersive">
        <ContentPreviewProvider>
          <ChatMessage
            autoOpenPreviewPane
            isLatestMessage
            messageIndex={0}
            message={{
              id: '12',
              role: 'assistant',
              createdAt: '2020-01-01T00:00:00Z',
              threadID: '12',
              references: [],
              content: 'test',
            }}
          />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(await screen.findByTestId('retry-button')).toBeInTheDocument()
  })

  it('retry button renders when author is an agent', async () => {
    const agentRef = {
      type: 'github.agent',
      login: 'octocat-agent',
      avatarURL: 'https://github.com/octocat-agent.png',
    } as GitHubAgentReference

    render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="2" mode="immersive">
        <ContentPreviewProvider>
          <ChatMessage
            autoOpenPreviewPane
            isLatestMessage
            messageIndex={0}
            message={{
              id: '12',
              role: 'assistant',
              createdAt: '2020-01-01T00:00:00Z',
              threadID: '12',
              references: [agentRef],
              content: 'test',
            }}
          />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(await screen.findByTestId('retry-button')).toBeInTheDocument()
  })

  it('retry button is disabled when message reaches max number of threads', async () => {
    const messages: CopilotChatMessage[] = [
      {
        id: 'root',
        role: 'user',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: 'root',
        childMessageIndexes: [],
        selectedChildIndex: 1,
      },
    ]

    for (let i = 1; i <= 99; i++) {
      const message = {
        id: `${i}`,
        role: 'assistant',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: 'root',
        parentMessageIndex: 0,
        messageIndex: i,
      } as CopilotChatMessage
      messages.push(message)
      messages[0]!.childMessageIndexes!.push(i)
    }

    const chatProviderProps = {
      ...getCopilotChatProviderProps(),
      messages,
    }

    render(
      <CopilotChatProvider {...chatProviderProps} topic={undefined} threadId="2" mode="immersive">
        <ContentPreviewProvider>
          <ChatStateProvider
            state={{
              ...getDefaultReducerState('2', undefined, 'immersive'),
              messages,
            }}
          >
            <ChatMessage autoOpenPreviewPane isLatestMessage messageIndex={1} message={messages[1]!} />
          </ChatStateProvider>
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    const retryButton = await screen.findByLabelText('Retry')
    expect(retryButton).toBeInTheDocument()
    expect(retryButton).toBeDisabled()
  })

  // FIXME: We don't have a way to use mocking to override the maximum messages per thread. Maybe we should move this
  // constant into a top-level config on CopilotChatProvider?
  it.skip('retry button is disabled when the max number of messages is reached', async () => {
    const messages: CopilotChatMessage[] = []
    messages.push({
      id: 'root',
      role: 'user',
      createdAt: '2020-01-01T00:00:00Z',
      threadID: '12',
      references: [],
      content: 'test',
      parentMessageID: 'root',
      childMessageIndexes: [],
    })
    messages.push({
      id: '1',
      role: 'assistant',
      createdAt: '2020-01-01T00:00:00Z',
      threadID: '12',
      references: [],
      content: 'test',
      parentMessageID: 'root',
      parentMessageIndex: 0,
    })
    messages[0]!.childMessageIndexes = [1]

    render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        messages={messages}
        topic={undefined}
        threadId="2"
        mode="immersive"
      >
        <ContentPreviewProvider>
          <ChatMessage autoOpenPreviewPane isLatestMessage={false} messageIndex={1} message={messages[1]!} />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    const retryButton = await screen.findByLabelText('Retry')
    expect(retryButton).toBeInTheDocument()
    expect(retryButton).toBeDisabled()
  })

  it('retry button is disabled when the copilot space cannot be found', async () => {
    const chatProviderProps = {
      ...getCopilotChatProviderProps(),
      selectedThreadId: '3',
    }

    render(
      <CopilotChatProvider {...chatProviderProps} topic={undefined} threadId="3" mode="immersive">
        <ContentPreviewProvider>
          <ChatStateProvider
            state={{
              ...getDefaultReducerState('3', undefined, 'immersive'),
              threads: new Map([
                [
                  '3',
                  {
                    id: '3',
                    name: 'conversation 3',
                    createdAt: new Date().toISOString(),
                    updatedAt: new Date().toISOString(),
                    customCopilotID: 123,
                    customCopilotOwner: 'monalisa',
                  },
                ],
              ]),
            }}
          >
            <ChatMessage
              autoOpenPreviewPane
              isLatestMessage
              messageIndex={0}
              message={{
                id: '12',
                role: 'assistant',
                createdAt: '2020-01-01T00:00:00Z',
                threadID: '3',
                references: [],
                content: 'test',
              }}
            />
          </ChatStateProvider>
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    const retryButton = await screen.findByLabelText('Retry')
    expect(retryButton).toBeInTheDocument()
    expect(retryButton).toBeDisabled()
  })
})

describe('subthreading', () => {
  beforeEach(() => {
    mockPageURL('/copilot/c/thread-uuid')
  })

  it('renders subthread paging component on copilot messages', async () => {
    const messages: CopilotChatMessage[] = [
      {
        id: '1',
        role: 'user',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: 'root',
        childMessageIndexes: [1, 2],
        parentMessageIndex: 0,
      },
      {
        id: '2',
        role: 'assistant',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: '1',
        parentMessageIndex: 0,
      },
      {
        id: '3',
        role: 'assistant',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: '1',
        parentMessageIndex: 0,
      },
    ]

    const chatProviderProps = {
      ...getCopilotChatProviderProps(),
      messages,
    }

    render(
      <CopilotChatProvider {...chatProviderProps} topic={undefined} threadId="2" mode="immersive">
        <ContentPreviewProvider>
          <ChatMessage autoOpenPreviewPane isLatestMessage={false} messageIndex={1} message={messages[1]!} />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )
    expect(await screen.findByTestId('chat-paging-component')).toBeInTheDocument()
  })

  it('renders subthread paging component on user messages', async () => {
    const messages: CopilotChatMessage[] = [
      {
        id: 'root',
        role: 'user',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: 'root',
        selectedChildIndex: 1,
        childMessageIndexes: [1, 2],
      },
      {
        id: '1',
        role: 'user',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: 'root',
        parentMessageIndex: 0,
      },
      {
        id: '2',
        role: 'user',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: 'root',
        parentMessageIndex: 0,
      },
    ]

    const chatProviderProps = {
      ...getCopilotChatProviderProps(),
      messages,
    }

    render(
      <CopilotChatProvider {...chatProviderProps} topic={undefined} threadId="2" mode="immersive">
        <ContentPreviewProvider>
          <ChatMessage autoOpenPreviewPane isLatestMessage={false} messageIndex={1} message={messages[1]!} />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(await screen.findByTestId('chat-paging-component')).toBeInTheDocument()
  })

  it('renders subthread paging indicator on copilot messages', async () => {
    const messages: CopilotChatMessage[] = [
      {
        id: '1',
        role: 'user',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: 'root',
        childMessageIndexes: [1, 2],
      },
      {
        id: '2',
        role: 'assistant',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: '1',
        parentMessageIndex: 0,
      },
      {
        id: '3',
        role: 'assistant',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: '1',
        parentMessageIndex: 0,
      },
    ]

    const chatProviderProps = {
      ...getCopilotChatProviderProps(),
      messages,
    }

    render(
      <CopilotChatProvider {...chatProviderProps} topic={undefined} threadId="2" mode="immersive">
        <ContentPreviewProvider>
          <ChatMessage autoOpenPreviewPane isLatestMessage={false} messageIndex={1} message={messages[1]!} />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(await screen.findByTestId('chat-paging-indicator')).toBeInTheDocument()
  })

  it('does not render subthread paging indicator on copilot messages when latest message', () => {
    const messages: CopilotChatMessage[] = [
      {
        id: '1',
        role: 'user',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: 'root',
        childMessageIndexes: [1, 2],
      },
      {
        id: '2',
        role: 'assistant',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: '1',
        parentMessageIndex: 0,
      },
      {
        id: '3',
        role: 'assistant',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: '1',
        parentMessageIndex: 0,
      },
    ]

    const chatProviderProps = {
      ...getCopilotChatProviderProps(),
      messages,
    }

    render(
      <CopilotChatProvider {...chatProviderProps} topic={undefined} threadId="2" mode="immersive">
        <ContentPreviewProvider>
          <ChatMessage autoOpenPreviewPane isLatestMessage messageIndex={0} message={messages[0]!} />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(screen.queryByTestId('chat-paging-indicator')).not.toBeInTheDocument()
  })

  it('does not render subthread paging component on copilot messages when no subthreads', () => {
    render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="2" mode="immersive">
        <ContentPreviewProvider>
          <ChatMessage
            autoOpenPreviewPane
            isLatestMessage={false}
            messageIndex={0}
            message={{
              id: '12',
              role: 'assistant',
              createdAt: '2020-01-01T00:00:00Z',
              threadID: '12',
              references: [],
              content: 'test',
            }}
          />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(screen.queryByTestId('chat-paging-indicator')).not.toBeInTheDocument()
  })

  it('renders subthread paging indicator on user messages', async () => {
    const messages: CopilotChatMessage[] = [
      {
        id: 'root',
        role: 'user',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: 'root',
        childMessageIndexes: [1, 2],
        selectedChildIndex: 0,
      },
      {
        id: '1',
        role: 'user',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: 'root',
        parentMessageIndex: 0,
      },
      {
        id: '2',
        role: 'user',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: 'root',
        parentMessageIndex: 0,
      },
    ]

    const chatProviderProps = {
      ...getCopilotChatProviderProps(),
      messages,
    }

    render(
      <CopilotChatProvider {...chatProviderProps} topic={undefined} threadId="2" mode="immersive">
        <ContentPreviewProvider>
          <ChatMessage autoOpenPreviewPane isLatestMessage={false} messageIndex={1} message={messages[1]!} />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(await screen.findByTestId('chat-paging-indicator')).toBeInTheDocument()
  })

  it('does not render subthread paging indicator on user messages when no subthreads', () => {
    render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="2" mode="immersive">
        <ContentPreviewProvider>
          <ChatMessage
            autoOpenPreviewPane
            isLatestMessage={false}
            messageIndex={0}
            message={{
              id: '12',
              role: 'user',
              createdAt: '2020-01-01T00:00:00Z',
              threadID: '12',
              references: [],
              content: 'test',
            }}
          />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(screen.queryByTestId('chat-paging-indicator')).not.toBeInTheDocument()
  })
})

describe('editing', () => {
  beforeEach(() => {
    mockPageURL('/copilot/c/thread-uuid')
  })

  it('renders edit icon on user messages', async () => {
    const messages: CopilotChatMessage[] = [
      {
        id: 'root',
        role: 'user',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: 'root',
        childMessageIndexes: [1, 2],
        selectedChildIndex: 0,
      },
      {
        id: '1',
        role: 'user',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: 'root',
        parentMessageIndex: 0,
      },
      {
        id: '2',
        role: 'user',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: 'root',
        parentMessageIndex: 0,
      },
    ]

    const chatProviderProps = {
      ...getCopilotChatProviderProps(),
      messages,
    }

    render(
      <CopilotChatProvider {...chatProviderProps} topic={undefined} threadId="2" mode="immersive">
        <ContentPreviewProvider>
          <ChatMessage autoOpenPreviewPane isLatestMessage={false} messageIndex={0} message={messages[0]!} />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(await screen.findByText('Edit message')).toBeInTheDocument()
  })

  it('renders editing box instead of user messages when user clicks the edit button', async () => {
    const {user} = render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="2" mode="immersive">
        <ContentPreviewProvider>
          <ChatMessage
            autoOpenPreviewPane
            isLatestMessage={false}
            messageIndex={0}
            message={{
              id: '12',
              role: 'user',
              createdAt: '2020-01-01T00:00:00Z',
              threadID: '12',
              references: [],
              content: 'test',
            }}
          />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )
    expect(await screen.findByText('Edit message')).toBeInTheDocument()
    expect(screen.queryByTestId('user-message-edit-box')).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Cancel'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Send'})).not.toBeInTheDocument()

    // Simulate a user click event on the edit button
    const button = await screen.findByRole('button', {name: 'Edit message'})
    await user.click(button)

    expect(screen.getByTestId('user-message-edit-box')).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Send ( enter )'})).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Edit message'})).not.toBeInTheDocument()
  })

  it('removes editing box when user clicks Cancel button', async () => {
    const {user} = render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="2" mode="immersive">
        <ContentPreviewProvider>
          <ChatMessage
            autoOpenPreviewPane
            isLatestMessage={false}
            messageIndex={0}
            message={{
              id: '12',
              role: 'user',
              createdAt: '2020-01-01T00:00:00Z',
              threadID: '12',
              references: [],
              content: 'test',
            }}
          />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    // Simulate a user click event on the edit button
    const button = await screen.findByRole('button', {name: 'Edit message'})
    await user.click(button)

    expect(screen.getByTestId('user-message-edit-box')).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Send ( enter )'})).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Edit message'})).not.toBeInTheDocument()

    // Simulate a user click event on the cancel button
    const cancelButton = await screen.findByRole('button', {name: 'Cancel'})
    await user.click(cancelButton)

    expect(await screen.findByText('Edit message')).toBeInTheDocument()
    expect(screen.queryByTestId('user-message-edit-box')).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Cancel'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Send ( enter )'})).not.toBeInTheDocument()
  })

  it('disables send button in editing box while message is streaming', async () => {
    const {user} = render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        testReducerState={{
          ...getDefaultReducerState('2', undefined, 'immersive'),
          isWaitingOnCopilot: true,
        }}
      >
        <ContentPreviewProvider>
          <ChatMessage
            autoOpenPreviewPane
            isStreaming
            isLatestMessage={false}
            messageIndex={0}
            message={{
              id: '12',
              role: 'user',
              createdAt: '2020-01-01T00:00:00Z',
              threadID: '12',
              references: [],
              content: 'test',
            }}
          />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    // Simulate a user click event on the edit button
    const button = await screen.findByRole('button', {name: 'Edit message'})
    await user.click(button)

    expect(screen.getByTestId('user-message-edit-box')).toBeInTheDocument()
    const sendButton = screen.getByRole('button', {name: 'Send ( enter )'})
    expect(sendButton).toBeInTheDocument()
    expect(sendButton).toBeDisabled()
  })

  it('hides edit icon on user messages when message is streaming', () => {
    const messages: CopilotChatMessage[] = [
      {
        id: 'root',
        role: 'user',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: 'root',
        childMessageIndexes: [1, 2],
        selectedChildIndex: 0,
      },
      {
        id: '1',
        role: 'user',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: 'root',
        parentMessageIndex: 0,
      },
      {
        id: '2',
        role: 'user',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: 'root',
        parentMessageIndex: 0,
      },
    ]

    const chatProviderProps = {
      ...getCopilotChatProviderProps(),
      messages,
    }

    render(
      <CopilotChatProvider {...chatProviderProps} topic={undefined} threadId="2" mode="immersive">
        <ContentPreviewProvider>
          <ChatStateProvider
            state={{
              ...getDefaultReducerState('2', undefined, 'immersive'),
              isWaitingOnCopilot: true,
              messages,
            }}
          >
            <ChatMessage autoOpenPreviewPane isLatestMessage messageIndex={0} message={messages[0]!} />
          </ChatStateProvider>
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(screen.queryByLabelText('Edit message')).not.toBeInTheDocument()
  })

  it('hides edit icon on user messages when message is a create issue confirmation', () => {
    const messages: CopilotChatMessage[] = [
      {
        id: 'root',
        role: 'user',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: 'root',
        childMessageIndexes: [1, 2],
        selectedChildIndex: 0,
      },
      {
        id: '1',
        role: 'user',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: 'root',
        parentMessageIndex: 0,
      },
      {
        id: '2',
        role: 'user',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [
          {
            type: 'text',
            name: 'issue-created',
            text: 'test',
          },
        ],
        content: 'test',
        parentMessageID: 'root',
        parentMessageIndex: 0,
      },
    ]

    const chatProviderProps = {
      ...getCopilotChatProviderProps(),
      messages,
    }

    render(
      <CopilotChatProvider {...chatProviderProps} topic={undefined} threadId="2" mode="immersive">
        <ContentPreviewProvider>
          <ChatStateProvider
            state={{
              ...getDefaultReducerState('2', undefined, 'immersive'),
              isWaitingOnCopilot: true,
              messages,
            }}
          >
            <ChatMessage autoOpenPreviewPane isLatestMessage messageIndex={0} message={messages[0]!} />
          </ChatStateProvider>
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(screen.queryByLabelText('Edit message')).not.toBeInTheDocument()
  })

  it('disables edit icon on user messages when message reaches max number of threads', async () => {
    const messages: CopilotChatMessage[] = [
      {
        id: 'root',
        role: 'user',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: 'root',
        childMessageIndexes: [],
        selectedChildIndex: 0,
      },
    ]

    for (let i = 1; i <= 99; i++) {
      const message = {
        id: `${i}`,
        role: 'user',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: 'test',
        parentMessageID: 'root',
        parentMessageIndex: 0,
        messageIndex: i,
      } as CopilotChatMessage
      messages.push(message)
      messages[0]!.childMessageIndexes!.push(i)
    }

    const chatProviderProps = {
      ...getCopilotChatProviderProps(),
      messages,
    }

    render(
      <CopilotChatProvider {...chatProviderProps} topic={undefined} threadId="2" mode="immersive">
        <ContentPreviewProvider>
          <ChatStateProvider
            state={{
              ...getDefaultReducerState('2', undefined, 'immersive'),
              messages,
            }}
          >
            <ChatMessage autoOpenPreviewPane isLatestMessage={false} messageIndex={1} message={messages[1]!} />
          </ChatStateProvider>
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    const editButton = await screen.findByLabelText('Edit message')
    expect(editButton).toBeInTheDocument()
    expect(editButton).toBeDisabled()
  })

  it('disables edit icon on user messages when thread is tied to a deleted space', async () => {
    const chatProviderProps = {
      ...getCopilotChatProviderProps(),
      selectedThreadId: '3',
    }

    render(
      <CopilotChatProvider {...chatProviderProps} topic={undefined} threadId="3" mode="immersive">
        <ContentPreviewProvider>
          <ChatStateProvider
            state={{
              ...getDefaultReducerState('3', undefined, 'immersive'),
              threads: new Map([
                [
                  '3',
                  {
                    id: '3',
                    name: 'conversation 3',
                    createdAt: new Date().toISOString(),
                    updatedAt: new Date().toISOString(),
                    customCopilotID: 123,
                    customCopilotOwner: 'monalisa',
                  },
                ],
              ]),
            }}
          >
            <ChatMessage
              autoOpenPreviewPane
              isLatestMessage={false}
              messageIndex={0}
              message={{
                id: '1',
                role: 'user',
                createdAt: '2020-01-01T00:00:00Z',
                threadID: '3',
                references: [],
                content: 'test',
              }}
            />
          </ChatStateProvider>
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    const editButton = await screen.findByLabelText('Edit message')
    expect(editButton).toBeInTheDocument()
    expect(editButton).toBeDisabled()
  })
})

describe('message toolbar', () => {
  const firstMessage: CopilotChatMessage = {
    id: 'first-message',
    role: 'user',
    createdAt: '2025-03-20T12:01:00Z',
    threadID: 'thread-id',
    references: [],
    parentMessageID: 'root',
    parentMessageIndex: undefined,
    childMessageIndexes: [1, 2],
    content: 'first message from a human, has not been retried',
  }
  const origAssistantMessage: CopilotChatMessage = {
    id: 'orig-assistant-message',
    role: 'assistant',
    createdAt: '2025-03-20T12:13:00Z',
    threadID: 'thread-id',
    references: [],
    parentMessageID: 'first-message',
    parentMessageIndex: 0,
    childMessageIndexes: [],
    content: 'original assistant message from copilot',
  }
  const retriedAssistantMessage: CopilotChatMessage = {
    id: 'retried-assistant-message',
    role: 'assistant',
    createdAt: '2025-03-20T12:26:00Z',
    threadID: 'thread-id',
    references: [],
    parentMessageID: 'first-message',
    parentMessageIndex: 0,
    childMessageIndexes: [3, 4],
    content: 'retried assistant message from copilot',
  }
  const origUserMessage: CopilotChatMessage = {
    id: 'orig-user-message',
    role: 'user',
    createdAt: '2025-03-20T12:30:00Z',
    threadID: 'thread-id',
    references: [],
    parentMessageID: 'retried-assistant-message',
    parentMessageIndex: 2,
    childMessageIndexes: [],
    content: 'orig user message from human',
  }
  const retriedUserMessage: CopilotChatMessage = {
    id: 'retried-user-message',
    role: 'user',
    createdAt: '2025-03-20T12:42:00Z',
    threadID: 'thread-id',
    references: [],
    parentMessageID: 'retried-assistant-message',
    parentMessageIndex: 2,
    childMessageIndexes: [],
    content: 'retried user message from human',
  }
  const userMessageWithoutSubthread: CopilotChatMessage = {
    id: 'user-message-without-subthread',
    role: 'user',
    createdAt: '2025-03-20T12:19:00Z',
    threadID: 'thread-id',
    references: [],
    parentMessageID: 'orig-assistant-message',
    parentMessageIndex: 1,
    childMessageIndexes: [],
    content: 'user message whose parent does not have multiple children',
  }
  const assistantMessageWithoutSubthread: CopilotChatMessage = {
    id: 'assistant-message-without-subthread',
    role: 'assistant',
    createdAt: '2025-03-20T12:22:00Z',
    threadID: 'thread-id',
    references: [],
    parentMessageID: 'user-message-without-subthread',
    parentMessageIndex: 5,
    childMessageIndexes: [],
    content: 'assistant message whose parent does not have multiple children',
  }

  const messages: CopilotChatMessage[] = [
    firstMessage,
    origAssistantMessage,
    retriedAssistantMessage,
    origUserMessage,
    retriedUserMessage,
    userMessageWithoutSubthread,
    assistantMessageWithoutSubthread,
  ]

  const chatProviderProps = {
    ...getCopilotChatProviderProps(),
    messages,
  }

  it('shows thumbs up, thumbs down, copy, retry buttons, and paging UX for retried assistant messages', () => {
    mockPageURL('/copilot/c/my-conversation-thread-uuid')

    render(
      <CopilotChatProvider {...chatProviderProps} topic={undefined} threadId="thread-id" mode="immersive">
        <ContentPreviewProvider>
          <ChatMessage autoOpenPreviewPane isLatestMessage={false} messageIndex={2} message={retriedAssistantMessage} />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(screen.getByTestId('nonshared-toolbar')).toBeInTheDocument()
    expect(screen.getByTestId('chat-paging-indicator')).toBeInTheDocument()
    expect(screen.getByTestId('chat-paging-component')).toBeInTheDocument()

    expect(screen.getByRole('toolbar', {name: 'Message tools'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Good response'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Bad response'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Copy to clipboard'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Retry'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Previous response'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Next response'})).toBeInTheDocument()
  })

  it('shows only edit button and paging UX for retried user messages', () => {
    mockPageURL('/copilot/c/my-conversation-thread-uuid')

    render(
      <CopilotChatProvider {...chatProviderProps} topic={undefined} threadId="thread-id" mode="immersive">
        <ContentPreviewProvider>
          <ChatMessage autoOpenPreviewPane isLatestMessage={false} messageIndex={4} message={retriedUserMessage} />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(screen.getByTestId('nonshared-toolbar')).toBeInTheDocument()
    expect(screen.getByTestId('chat-paging-indicator')).toBeInTheDocument()
    expect(screen.getByTestId('chat-paging-component')).toBeInTheDocument()

    expect(screen.getByRole('toolbar', {name: 'Message tools'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Edit message'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Previous response'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Next response'})).toBeInTheDocument()

    expect(screen.queryByRole('button', {name: 'Good response'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Bad response'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Copy to clipboard'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Retry'})).not.toBeInTheDocument()
  })

  it('shows copy button and paging UX for retried assistant messages in a shared conversation', () => {
    mockPageURL('/copilot/share/shared-thread-uuid')

    render(
      <CopilotChatProvider {...chatProviderProps} topic={undefined} threadId="thread-id" mode="immersive">
        <ContentPreviewProvider>
          <ChatMessage autoOpenPreviewPane isLatestMessage={false} messageIndex={2} message={retriedAssistantMessage} />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(screen.getByTestId('shared-toolbar')).toBeInTheDocument()
    expect(screen.getByTestId('chat-paging-indicator')).toBeInTheDocument()
    expect(screen.getByTestId('chat-paging-component')).toBeInTheDocument()

    expect(screen.getByRole('toolbar', {name: 'Message tools'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Copy to clipboard'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Previous response'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Next response'})).toBeInTheDocument()

    expect(screen.queryByRole('button', {name: 'Edit message'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Good response'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Bad response'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Retry'})).not.toBeInTheDocument()
  })

  it('shows only copy button for non-retried assistant message without subthreads in a shared conversation', () => {
    mockPageURL('/copilot/share/shared-thread-uuid')

    render(
      <CopilotChatProvider {...chatProviderProps} topic={undefined} threadId="thread-id" mode="immersive">
        <ContentPreviewProvider>
          <ChatMessage
            autoOpenPreviewPane
            isLatestMessage={false}
            messageIndex={6}
            message={assistantMessageWithoutSubthread}
          />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(screen.getByTestId('shared-toolbar')).toBeInTheDocument()
    expect(screen.queryByTestId('chat-paging-indicator')).not.toBeInTheDocument()
    expect(screen.queryByTestId('chat-paging-component')).not.toBeInTheDocument()

    expect(screen.getByRole('toolbar', {name: 'Message tools'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Copy to clipboard'})).toBeInTheDocument()

    expect(screen.queryByRole('button', {name: 'Edit message'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Good response'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Bad response'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Retry'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Previous response'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Next response'})).not.toBeInTheDocument()
  })

  it('shows only paging UX for retried user messages in a shared conversation', () => {
    mockPageURL('/copilot/share/shared-thread-uuid')

    render(
      <CopilotChatProvider {...chatProviderProps} topic={undefined} threadId="thread-id" mode="immersive">
        <ContentPreviewProvider>
          <ChatMessage autoOpenPreviewPane isLatestMessage={false} messageIndex={4} message={retriedUserMessage} />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(screen.getByTestId('shared-toolbar')).toBeInTheDocument()
    expect(screen.getByTestId('chat-paging-indicator')).toBeInTheDocument()
    expect(screen.getByTestId('chat-paging-component')).toBeInTheDocument()

    expect(screen.getByRole('toolbar', {name: 'Message tools'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Previous response'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Next response'})).toBeInTheDocument()

    expect(screen.queryByRole('button', {name: 'Edit message'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Good response'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Bad response'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Copy to clipboard'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Retry'})).not.toBeInTheDocument()
  })

  it('does not show up for a non-retried user message without subthreads in a shared conversation', () => {
    mockPageURL('/copilot/share/shared-thread-uuid')

    render(
      <CopilotChatProvider {...chatProviderProps} topic={undefined} threadId="thread-id" mode="immersive">
        <ContentPreviewProvider>
          <ChatMessage
            autoOpenPreviewPane
            isLatestMessage={false}
            messageIndex={5}
            message={userMessageWithoutSubthread}
          />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(screen.queryByTestId('liveshared-toolbar')).not.toBeInTheDocument()
    expect(screen.queryByTestId('chat-paging-indicator')).not.toBeInTheDocument()
    expect(screen.queryByTestId('chat-paging-component')).not.toBeInTheDocument()

    expect(screen.queryByRole('toolbar', {name: 'Message tools'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Edit message'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Good response'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Bad response'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Copy to clipboard'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Retry'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Previous response'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Next response'})).not.toBeInTheDocument()
  })
})

describe('user message markdown rendering', () => {
  beforeEach(() => {
    mockPageURL('/copilot/c/thread-uuid')
  })

  it('user messages do not render markdown', () => {
    const messages: CopilotChatMessage[] = [
      {
        id: 'root',
        role: 'user',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [],
        content: '[a link](https://github.com)',
        parentMessageID: 'root',
        childMessageIndexes: [1, 2],
        selectedChildIndex: 0,
      },
    ]

    const chatProviderProps = {
      ...getCopilotChatProviderProps(),
      messages,
    }

    render(
      <CopilotChatProvider {...chatProviderProps} topic={undefined} threadId="2" mode="immersive">
        <ContentPreviewProvider>
          <ChatStateProvider
            state={{
              ...getDefaultReducerState('0', undefined, 'immersive'),
              isWaitingOnCopilot: true,
              messages,
            }}
          >
            <ChatMessage autoOpenPreviewPane isLatestMessage messageIndex={0} message={messages[0]!} />
          </ChatStateProvider>
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(screen.getByText('[a link](https://github.com)')).toBeInTheDocument()
    expect(screen.queryByRole('link', {name: 'a link'})).not.toBeInTheDocument()
  })

  it('create issue confirmation message renders markdown links', () => {
    const messages: CopilotChatMessage[] = [
      {
        id: 'root',
        role: 'user',
        createdAt: '2020-01-01T00:00:00Z',
        threadID: '12',
        references: [
          {
            type: 'text',
            name: `timeline-event: {"type": "issue-created", "markdownContent": "Issue saved to [a link](https://github.com)"}`,
            text: '[a link](https://github.com)',
          },
        ],
        content: '[a link](https://github.com)',
        parentMessageID: 'root',
        childMessageIndexes: [1, 2],
        selectedChildIndex: 0,
      },
    ]

    const chatProviderProps = {
      ...getCopilotChatProviderProps(),
      messages,
    }

    render(
      <CopilotChatProvider {...chatProviderProps} topic={undefined} threadId="2" mode="immersive">
        <ContentPreviewProvider>
          <ChatStateProvider
            state={{
              ...getDefaultReducerState('0', undefined, 'immersive'),
              isWaitingOnCopilot: true,
              messages,
            }}
          >
            <ChatMessage autoOpenPreviewPane isLatestMessage messageIndex={0} message={messages[0]!} />
          </ChatStateProvider>
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(screen.getByRole('link', {name: 'a link'})).toBeInTheDocument()
  })
})

it('Does not render ChatMessage if message is a timeline event', () => {
  render(
    <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="2" mode="immersive">
      <ContentPreviewProvider>
        <ChatMessage
          autoOpenPreviewPane
          isLatestMessage
          messageIndex={0}
          message={{
            id: '12',
            role: 'user',
            createdAt: '2020-01-01T00:00:00Z',
            threadID: '12',
            references: [
              {
                type: 'text',
                name: 'timeline-event: {"type": "issue-created", "markdownContent": "timeline event text"}',
              },
            ],
            content: 'test',
          }}
        />
      </ContentPreviewProvider>
    </CopilotChatProvider>,
  )

  expect(screen.queryByTestId('message-12')).not.toBeInTheDocument()
})

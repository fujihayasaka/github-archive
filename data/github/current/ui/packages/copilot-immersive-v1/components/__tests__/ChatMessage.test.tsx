import {getCopilotChatProviderProps, getDefaultReducerState} from '@github-ui/copilot-chat/test-utils/mock-data'
import type {CopilotChatMessage, GitHubAgentReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {ChatStateProvider, CopilotChatProvider} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {useLocation} from 'react-router-dom'

import {ChatMessage} from '../ChatMessage'
import {ContentPreviewProvider} from '../ContentPreview/ContentPreviewContext'

let maxMessagesReached = jest.fn()
jest.mock('../../../copilot-chat/utils/CopilotChatManagerContext', () => {
  return {
    ...jest.requireActual('../../../copilot-chat/utils/CopilotChatManagerContext'),
    useChatManager: () => {
      return {
        maxMessagesReached,
      }
    },
  }
})

jest.mock('react-router-dom', () => ({...jest.requireActual('react-router-dom'), useLocation: jest.fn()}))
const mockedUseLocation = jest.mocked(useLocation)

beforeEach(() => {
  maxMessagesReached = jest.fn(() => false)
  mockedUseLocation.mockReturnValue({state: '', key: '', pathname: '', search: '', hash: ''})
})

describe('retry button', () => {
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
    jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(true)

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

  it('retry button does not render by default when subthreading flag is disabled', () => {
    jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(false)

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

    expect(screen.queryByTestId('retry-button')).not.toBeInTheDocument()
  })

  it('retry button renders by default when subthreading flag is enabled', async () => {
    jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(true)

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

  it('retry button renders when author is an agent and subthreading flag is enabled', async () => {
    jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(true)

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
    jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(true)

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

  it('retry button is disabled when the max number of messages is reached', async () => {
    maxMessagesReached = jest.fn(() => true)
    jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(true)

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

    expect(maxMessagesReached).toHaveBeenCalled()

    const retryButton = await screen.findByLabelText('Retry')
    expect(retryButton).toBeInTheDocument()
    expect(retryButton).toBeDisabled()
  })
})

describe('subthreading', () => {
  it('renders subthread paging component on copilot messages when flag is enabled', async () => {
    jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(true)
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

  it('does not render subthread paging component on copilot messages when flag is disabled', () => {
    jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(false)

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

    expect(screen.queryByTestId('chat-paging-component')).not.toBeInTheDocument()
  })

  it('renders subthread paging component on user messages when flag is enabled', async () => {
    jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(true)
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

  it('does not render subthread paging component on user messages when flag is disabled', () => {
    jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(false)

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
              references: [],
              content: 'test',
            }}
          />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(screen.queryByTestId('chat-paging-component')).not.toBeInTheDocument()
  })

  it('renders subthread paging indicator on copilot messages when flag is enabled', async () => {
    jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(true)
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
    jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(true)
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
    jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(true)

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

  it('renders subthread paging indicator on user messages when flag is enabled', async () => {
    jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(true)
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
    jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(true)

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
  it('renders edit icon on user messages when flag is enabled', async () => {
    jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(true)

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

  it('does not render edit icon on user messages when flag is disabled', () => {
    jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(false)

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
              references: [],
              content: 'test',
            }}
          />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(screen.queryByRole('button', {name: 'Edit message'})).not.toBeInTheDocument()
  })

  it('renders editing box instead of user messages when user clicks the edit button and flag is enabled', async () => {
    jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(true)

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
    expect(screen.getByRole('button', {name: 'Send'})).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Edit message'})).not.toBeInTheDocument()
  })

  it('does not render editing box instead of user messages when editing and flag is disabled', () => {
    jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(false)

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
              references: [],
              content: 'test',
            }}
          />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(screen.queryByRole('button', {name: 'Edit Message'})).not.toBeInTheDocument()
  })

  it('removes editing box when user clicks Cancel button and flag is enabled', async () => {
    jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(true)

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
    expect(screen.getByRole('button', {name: 'Send'})).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Edit message'})).not.toBeInTheDocument()

    // Simulate a user click event on the cancel button
    const cancelButton = await screen.findByRole('button', {name: 'Cancel'})
    await user.click(cancelButton)

    expect(await screen.findByText('Edit message')).toBeInTheDocument()
    expect(screen.queryByTestId('user-message-edit-box')).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Cancel'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Send'})).not.toBeInTheDocument()
  })

  it('disables send button in editing box while message is streaming and flag is enabled', async () => {
    jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(true)

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
    const sendButton = screen.getByRole('button', {name: 'Send'})
    expect(sendButton).toBeInTheDocument()
    expect(sendButton).toBeDisabled()
  })

  it('hides edit icon on user messages when message is streaming', () => {
    jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(true)

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

  it('disables edit icon on user messages when message reaches max number of threads', async () => {
    jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(true)

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
})

describe('shared thread mode', () => {
  it('shows only copy button in shared thread mode', () => {
    // Explicitly set the pathname to trigger isSharedThread
    mockedUseLocation.mockReturnValue({state: '', key: 'k1', pathname: '/share/some-thread-id', search: '', hash: ''})

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
              content: 'test content',
            }}
          />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(screen.getByRole('button', {name: 'Copy to clipboard'})).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Edit message'})).not.toBeInTheDocument()
    expect(screen.queryByTestId('retry-button')).not.toBeInTheDocument()
  })
})

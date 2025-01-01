import {Wrapper} from '@github-ui/react-core/test-utils'
import {renderRelay} from '@github-ui/relay-test-utils'
import {screen} from '@testing-library/react'

import {getCopilotChatProviderProps} from '../../test-utils/mock-data'
import type {CopilotChatMessage} from '../../utils/copilot-chat-types'
import {CopilotChatProvider} from '../../utils/CopilotChatContext'
import {ChatInput} from '../ChatInput'

const maxMessagesReached = jest.fn(() => true)
const cancelThreadReload = jest.fn(() => true)
jest.mock('../../../copilot-chat/utils/CopilotChatManagerContext', () => {
  return {
    ...jest.requireActual('../../../copilot-chat/utils/CopilotChatManagerContext'),
    useChatManager: () => {
      return {
        maxMessagesReached,
        cancelThreadReload,
        getSelectedThread: jest.fn(),
        setTopRepositoryTopics: jest.fn(),
      }
    },
  }
})

test('Renders the ChatInput', () => {
  renderRelay(
    () => (
      <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined}>
        <ChatInput />
      </CopilotChatProvider>
    ),
    {
      relay: {
        queries: {},
      },
      wrapper: Wrapper,
    },
  )
  expect(screen.getByTestId('copilot-chat-input-textarea')).toBeInTheDocument()
})

it('is disabled when the max number of messages is reached', async () => {
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

  renderRelay(
    () => (
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        messages={messages}
        topic={undefined}
        threadId="2"
        mode="immersive"
      >
        <ChatInput />
      </CopilotChatProvider>
    ),
    {
      relay: {
        queries: {},
      },
      wrapper: Wrapper,
    },
  )

  expect(maxMessagesReached).toHaveBeenCalled()

  const textArea = await screen.findByRole('textbox')
  expect(textArea.getAttribute('placeholder')).toBe(
    'Message limit reached. To continue chatting with Copilot, start a new conversation.',
  )
  expect(textArea).toBeInTheDocument()
  expect(textArea).toBeDisabled()
})

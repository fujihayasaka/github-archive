import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {getCopilotChatProviderProps} from '../../test-utils/mock-data'
import type {CopilotChatMessage} from '../../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../../utils/copilot-feature-flags'
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
      }
    },
  }
})

it('is disabled when the max number of messages is reached', async () => {
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
      <ChatInput />
    </CopilotChatProvider>,
  )

  expect(maxMessagesReached).toHaveBeenCalled()

  const textArea = await screen.findByRole('textbox')
  expect(textArea.getAttribute('placeholder')).toBe(
    'Message limit reached. To continue chatting with Copilot, start a new conversation.',
  )
  expect(textArea).toBeInTheDocument()
  expect(textArea).toBeDisabled()
})

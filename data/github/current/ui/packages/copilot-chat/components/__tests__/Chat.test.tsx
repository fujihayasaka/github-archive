import {sendEvent} from '@github-ui/hydro-analytics'
import {render} from '@github-ui/react-core/test-utils'
import {fireEvent, screen} from '@testing-library/react'

import {
  getCopilotChatProviderProps,
  getDefaultReducerState,
  getMessageMock,
  getThreadMock,
} from '../../test-utils/mock-data'
import {setupResizeObserverMock} from '../../test-utils/mock-resize-observer'
import {constructMessagesHierarchy} from '../../utils/copilot-chat-subthreading-helpers'
import type {CopilotChatMessage} from '../../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../../utils/copilot-feature-flags'
import {CopilotChatProvider} from '../../utils/CopilotChatContext'
import {Chat} from '../Chat'

jest.mock('@github-ui/hydro-analytics', () => {
  return {
    ...jest.requireActual('@github-ui/hydro-analytics'),
    sendEvent: jest.fn(),
  }
})

jest.mock('@github-ui/feature-flags')

test('Show suggested prompts when no topic is selected but in a thread', () => {
  setupResizeObserverMock()
  setupMatchMediaMock()
  render(
    <CopilotChatProvider
      {...getCopilotChatProviderProps()}
      testReducerState={{
        ...getDefaultReducerState('2', undefined, 'immersive'),
        topicLoading: {state: 'loaded', error: null},
        messagesLoading: {state: 'loaded', error: null},
        knowledgeBasesLoading: {state: 'loaded', error: null},
        threads: new Map([['2', {...getThreadMock(), id: '2'}]]),
      }}
    >
      <Chat />
    </CopilotChatProvider>,
  )

  const button = screen.getAllByRole('button')[1]! // This fixed index is not great, but the text of the buttons is randomized.
  expect(button).toBeInTheDocument()
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(button)

  const calls = (sendEvent as jest.Mock).mock.calls
  const eventIndex = calls.findIndex(call => call[0] === 'copilot_chat_suggestion_click')
  expect(eventIndex).toBeGreaterThan(-1)
  expect(calls[eventIndex][1]['content']).toBeUndefined()

  // Expect Copilot suggestions to be hidden
  expect(screen.queryByText('Ask anything:')).not.toBeInTheDocument()
})

test('Hide suggested prompts when in a thread with messages and no topic is selected', () => {
  setupResizeObserverMock()
  setupMatchMediaMock()

  render(
    <CopilotChatProvider
      {...getCopilotChatProviderProps()}
      testReducerState={{
        ...getDefaultReducerState('2', undefined, 'immersive'),
        topicLoading: {state: 'loaded', error: null},
        messagesLoading: {state: 'loaded', error: null},
        knowledgeBasesLoading: {state: 'loaded', error: null},
        threads: new Map([['2', {...getThreadMock(), id: '2', messages: [getMessageMock()]}]]),
      }}
    >
      <Chat />
    </CopilotChatProvider>,
  )
  const button = screen.getAllByRole('button')[1] // This fixed index is not great, but the text of the buttons is randomized.
  expect(button).toBeDefined()
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(button!)
  const suggestionButton = screen.getAllByRole('button')[6] // Skip past header buttons
  expect(suggestionButton).toBeUndefined()
})

test('Show actions on last Copilot response', async () => {
  jest.spyOn(copilotFeatureFlags, 'immersiveSubthreading', 'get').mockReturnValue(true)

  let messages: CopilotChatMessage[] = [
    {
      role: 'user',
      id: '1',
      content: 'test user message',
      createdAt: '2020-01-01T00:00:00Z',
      references: [],
      threadID: '2',
      parentMessageID: 'root',
    },
    {
      role: 'assistant',
      id: '2',
      content: 'test completion',
      createdAt: '2020-01-01T00:01:00Z',
      references: [],
      threadID: '2',
      parentMessageID: '1',
    },
  ]
  messages = constructMessagesHierarchy(messages)

  render(
    <CopilotChatProvider
      {...getCopilotChatProviderProps()}
      testReducerState={{
        ...getDefaultReducerState('2', undefined, 'immersive'),
        topicLoading: {state: 'loaded', error: null},
        messagesLoading: {state: 'loaded', error: null},
        threads: new Map([['2', {...getThreadMock(), id: '2'}]]),
        messages,
      }}
    >
      <Chat />
    </CopilotChatProvider>,
  )

  const actionBars = await screen.findAllByTestId('message-action-bar')
  expect(actionBars.length === 2).toBeTruthy()

  // The first action bar is invisible:
  expect(actionBars[0]).toBeInTheDocument()
  expect(actionBars[0]).not.toBeVisible()

  // The last message should have a visible action bar:
  expect(actionBars[1]).toBeInTheDocument()
  expect(actionBars[1]).toBeVisible()
})

function setupMatchMediaMock() {
  /**
   * Duplicated from ui/packages/jest/jest-setup.ts
   * this is not implemented in JSDOM, and until it is we'll need to polyfill
   */
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: jest.fn().mockImplementation(query => {
      return {
        matches: false,
        media: query,
        onchange: null,
        addListener: jest.fn(), // deprecated
        removeListener: jest.fn(), // deprecated
        addEventListener: jest.fn(),
        removeEventListener: jest.fn(),
        dispatchEvent: jest.fn(),
      }
    }),
  })
}

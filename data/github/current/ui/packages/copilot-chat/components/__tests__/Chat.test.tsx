import {isFeatureEnabled} from '@github-ui/feature-flags'
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

test('`Ask anything:` is in the Suggestions header when messages array is empty and context is undefined', () => {
  setupResizeObserverMock()
  setupMatchMediaMock()
  ;(isFeatureEnabled as jest.Mock).mockImplementation(flag => flag === 'copilot_chat_static_thread_suggestions')

  render(
    <CopilotChatProvider
      {...getCopilotChatProviderProps()}
      testReducerState={{
        ...getDefaultReducerState('2', undefined, 'assistive'),
        messagesLoading: {state: 'loaded', error: null},
        topicLoading: {state: 'loaded', error: null},
        currentReferences: [],
        suggestions: {referenceType: undefined, suggestions: [{question: 'Tell me about this repo.', skill: ''}]},
        threads: new Map([['2', {...getThreadMock(), id: '2', messages: []}]]),
        context: undefined,
        currentTopic: {
          id: 4,
          name: 'smile',
          ownerLogin: 'monalisa',
          ownerType: 'User',
          readmePath: undefined,
          description:
            "The Jedi are extinct. Their fire has gone out of the universe. You, my friend, are all that's left of their religion.",
          commitOID: '97820b05f0cda85ee1179589b3bbb13e163107d8',
          ref: 'refs/heads/main',
          refInfo: {
            name: 'main',
            type: 'branch',
          },
          visibility: 'public',
          languages: [],
        },
      }}
    >
      <Chat />
    </CopilotChatProvider>,
  )

  // Expect 'Ask anything' to be the header
  expect(screen.getByText('Ask anything:')).toBeInTheDocument()

  // Expect copilot_generated_suggestion_click to be called when a Copilot suggestion is clicked
  const li = screen.getAllByRole('listitem')[0]! // This fixed index is not great, but the text of the list items is randomized.
  expect(li).toBeInTheDocument()
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(li)

  const calls = (sendEvent as jest.Mock).mock.calls
  const eventIndex = calls.findIndex(call => call[0] === 'copilot_generated_suggestion_click')
  expect(eventIndex).toBeGreaterThan(-1)
  expect(calls[eventIndex][0]['content']).toBeUndefined()
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

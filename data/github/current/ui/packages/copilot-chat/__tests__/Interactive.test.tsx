// This test suite tests end to end experiences of the assistive copilot chat
// Entire stack is tested, with mocked fetch responses

import {render} from '@github-ui/react-core/test-utils'
import {act, screen, within} from '@testing-library/react'

import {CopilotChat} from '../CopilotChat'
import {getCopilotChatProps} from '../test-utils/mock-data'
import type {FetchDefinition} from '../test-utils/mock-interactive'
import {mockEventStreamResponse, mockResponses} from '../test-utils/mock-interactive'
import {copilotLocalStorage} from '../utils/copilot-local-storage'

// The import mocks have to be in test file due to jest behaviors (e.g. hoisting)
jest.mock('@github-ui/react-core/use-app-payload')
jest.mock('@github-ui/ssr-utils', () => ({
  ...jest.requireActual('@github-ui/ssr-utils'),
  // Allows safe-storage module to use local storage
  ssrSafeWindow: window,
  // Provides the current page location
  ssrSafeLocation: {origin: 'https://github.localhost', pathname: '/github/github'},
}))

beforeEach(() => {
  // Store current thread ID in local storage so that chat opens it
  copilotLocalStorage.selectedThreadID = '123'
})

afterEach(() => {
  // Reset timers so that act() works when tests run concurrently
  jest.useRealTimers()
})

// Returns the initial fetches for an existing thread
// This can be mutated to keep track of fetches that have already completed
function getInitialFetches(): FetchDefinition[] {
  return JSON.parse(
    JSON.stringify([
      {
        request: {
          // Assistive chat uses latest endpoint and loads single thread
          url: '/github/chat/threads/latest?thread_id=123',
          method: 'GET',
        },
        response: {
          thread: {
            id: '123',
            name: 'Thread Name',
            repoID: 0,
            repoOwnerID: 0,
            associatedRepoIDs: [],
            updatedAt: new Date().toString(),
          },
        },
      },
      {
        request: {url: '/github/chat/threads/123/messages', method: 'GET'},
        response: {
          thread: {id: '123'},
          messages: [
            {
              id: '1',
              parentMessageID: 'root',
              role: 'user',
              content: 'First message',
              threadID: '123',
            },
            {
              id: '2',
              parentMessageID: '1',
              role: 'assistant',
              content: 'First reply',
              threadID: '123',
            },
          ],
        },
      },
    ]),
  )
}

describe('Adding content to thread', () => {
  test('Sends new message to an existing thread', async () => {
    const fetches = [
      ...getInitialFetches(),
      {
        request: {
          url: '/github/chat/threads/123/messages?',
          method: 'POST',
          body: {
            content: 'Hi Copilot!',
            intent: 'conversation',
            streaming: true,
            mode: 'assistive',
            parentMessageID: '2',
          },
        },
        // Returns assistant message ID and the generated user message ID
        response: mockEventStreamResponse('Hello!', {id: '4', parentMessageID: '3', role: 'assistant'}),
      },
    ]

    let fetchCount = 0
    mockResponses(fetches, () => fetchCount++)

    // Render thread in assistive, regardless of references match
    const {user} = render(<CopilotChat {...getCopilotChatProps()} currentTopic={undefined} apiURL="" />)

    // Open assistive panel using copilot button
    const copilotButton = await screen.findByTestId('copilot-chat-button')
    act(() => {
      copilotButton.click()
    })

    let message1 = await screen.findByTestId('message-1')
    let message2 = await screen.findByTestId('message-2')
    expect(await within(message1).findByText('First message')).toBeVisible()
    expect(await within(message2).findByText('First reply')).toBeVisible()

    const textArea = await screen.findByTestId('copilot-chat-input-textarea')
    await user.type(textArea, 'Hi Copilot!')
    await user.keyboard('{enter}')

    message1 = await screen.findByTestId('message-1')
    message2 = await screen.findByTestId('message-2')
    expect(await within(message1).findByText('First message')).toBeVisible()
    expect(await within(message2).findByText('First reply')).toBeVisible()
    const message3 = await screen.findByTestId('message-3')
    const message4 = await screen.findByTestId('message-4')
    expect(message3).toBeVisible()
    expect(message4).toBeVisible()
    expect(await within(message3).findByText('Hi Copilot!')).toBeVisible()
    expect(await within(message4).findByText('Hello!')).toBeVisible()

    expect(fetchCount).toBe(fetches.length)
  })
})

describe('Rendering a thread', () => {
  test('Renders most recent subthread', async () => {
    const fetches = [
      {
        request: {
          // Assistive chat uses latest endpoint and loads single thread
          url: '/github/chat/threads/latest?thread_id=123',
          method: 'GET',
        },
        response: {
          thread: {
            id: '123',
            name: 'Thread Name',
            repoID: 0,
            repoOwnerID: 0,
            associatedRepoIDs: [],
            updatedAt: new Date().toString(),
          },
        },
      },
      {
        request: {url: '/github/chat/threads/123/messages', method: 'GET'},
        response: {
          thread: {id: '123'},
          messages: [
            {
              id: '1',
              parentMessageID: 'root',
              role: 'user',
              content: 'First message',
              threadID: '123',
            },
            {
              id: '2',
              parentMessageID: '1',
              role: 'assistant',
              content: 'First reply',
              threadID: '123',
            },
            {
              id: '3',
              parentMessageID: '1',
              role: 'assistant',
              content: 'Second reply',
              threadID: '123',
            },
          ],
        },
      },
    ]

    let fetchCount = 0
    mockResponses(fetches, () => fetchCount++)

    // Render thread in assistive, regardless of references match
    render(<CopilotChat {...getCopilotChatProps()} currentTopic={undefined} apiURL="" />)

    // Open assistive panel using copilot button
    const copilotButton = await screen.findByTestId('copilot-chat-button')
    act(() => {
      copilotButton.click()
    })

    const message1 = await screen.findByTestId('message-1')
    const message3 = await screen.findByTestId('message-3')
    expect(await within(message1).findByText('First message')).toBeVisible()
    expect(await within(message3).findByText('Second reply')).toBeVisible()

    // Hidden subthread message should be invisible
    expect(screen.queryByTestId('message-2')).toBeNull()

    expect(fetchCount).toBe(fetches.length)
  })

  test('Renders thread without subthread information', async () => {
    const fetches = [
      {
        request: {
          // Assistive chat uses latest endpoint and loads single thread
          url: '/github/chat/threads/latest?thread_id=123',
          method: 'GET',
        },
        response: {
          thread: {
            id: '123',
            name: 'Thread Name',
            repoID: 0,
            repoOwnerID: 0,
            associatedRepoIDs: [],
            updatedAt: new Date().toString(),
          },
        },
      },
      {
        request: {url: '/github/chat/threads/123/messages', method: 'GET'},
        response: {
          thread: {id: '123'},
          messages: [
            {
              id: '1',
              role: 'user',
              content: 'First message',
              threadID: '123',
            },
            {
              id: '2',
              role: 'assistant',
              content: 'First reply',
              threadID: '123',
            },
            {
              id: '3',
              role: 'user',
              content: 'Second message',
              threadID: '123',
            },
            {
              id: '4',
              role: 'assistant',
              content: 'Second reply',
              threadID: '123',
            },
          ],
        },
      },
    ]

    let fetchCount = 0
    mockResponses(fetches, () => fetchCount++)

    // Render thread in assistive, regardless of references match
    render(<CopilotChat {...getCopilotChatProps()} currentTopic={undefined} apiURL="" />)

    // Open assistive panel using copilot button
    const copilotButton = await screen.findByTestId('copilot-chat-button')
    act(() => {
      copilotButton.click()
    })

    const message1 = await screen.findByTestId('message-1')
    const message2 = await screen.findByTestId('message-2')
    const message3 = await screen.findByTestId('message-3')
    const message4 = await screen.findByTestId('message-4')
    expect(await within(message1).findByText('First message')).toBeVisible()
    expect(await within(message2).findByText('First reply')).toBeVisible()
    expect(await within(message3).findByText('Second message')).toBeVisible()
    expect(await within(message4).findByText('Second reply')).toBeVisible()

    expect(fetchCount).toBe(fetches.length)
  })
})

describe('Interrupting copilot reply', () => {
  test('Interrupting new message to an existing thread', async () => {
    const fetches = [
      ...getInitialFetches(),
      {
        request: {
          url: '/github/chat/threads/123/messages?',
          method: 'POST',
          body: {
            content: 'Hi Copilot!',
            intent: 'conversation',
            streaming: true,
            mode: 'assistive',
            parentMessageID: '2',
          },
        },
        // An ongoing stream without complete payload
        response: mockEventStreamResponse('Interrupted reply'),
      },
      {
        request: {url: '/github/chat/threads/123/messages', method: 'GET'},
        response: {
          thread: {id: '123'},
          messages: [
            {
              id: '1',
              parentMessageID: 'root',
              role: 'user',
              content: 'First message',
              threadID: '123',
            },
            {
              id: '2',
              parentMessageID: '1',
              role: 'assistant',
              content: 'First reply',
              threadID: '123',
            },
            {
              id: '3',
              parentMessageID: '2',
              role: 'user',
              content: 'Second message',
              threadID: '123',
            },
            {
              id: '4',
              parentMessageID: '3',
              role: 'assistant',
              content: 'Interrupted reply',
              threadID: '123',
              interrupted: true,
            },
          ],
        },
      },
    ]

    let fetchCount = 0
    mockResponses(fetches, () => fetchCount++)

    // Render thread in assistive, regardless of references match
    const {user} = render(<CopilotChat {...getCopilotChatProps()} currentTopic={undefined} apiURL="" />)

    // Open assistive panel using copilot button
    const copilotButton = await screen.findByTestId('copilot-chat-button')
    act(() => {
      copilotButton.click()
    })

    let message1 = await screen.findByTestId('message-1')
    let message2 = await screen.findByTestId('message-2')
    expect(await within(message1).findByText('First message')).toBeVisible()
    expect(await within(message2).findByText('First reply')).toBeVisible()

    const textArea = await screen.findByTestId('copilot-chat-input-textarea')
    await user.type(textArea, 'Hi Copilot!')
    await user.keyboard('{enter}')

    const streamingMessage = await screen.findByTestId('message-streaming')
    expect(streamingMessage).toBeVisible()
    expect(await within(streamingMessage).findByText('Interrupted reply')).toBeVisible()

    jest.useFakeTimers()

    await user.keyboard('{Escape}')
    expect(await within(streamingMessage).findByTestId('chat-message-interrupted')).toBeVisible()

    // Allow thread to be reloaded from server
    // CopilotAnimation.tsx does internal state updates while waiting for data
    act(() => {
      jest.runAllTimers()
    })

    message1 = await screen.findByTestId('message-1')
    message2 = await screen.findByTestId('message-2')
    const message3 = await screen.findByTestId('message-3')
    const message4 = await screen.findByTestId('message-4')
    expect(await within(message1).findByText('First message')).toBeVisible()
    expect(await within(message2).findByText('First reply')).toBeVisible()
    expect(await within(message3).findByText('Second message')).toBeVisible()
    expect(await within(message4).findByText('Interrupted reply')).toBeVisible()

    expect(fetchCount).toBe(fetches.length)
  })
})

describe('Confirmations', () => {
  test('Rendering when adding new message to existing thread', async () => {
    const fetches = [
      ...getInitialFetches(),
      {
        request: {
          url: '/github/chat/threads/123/messages?',
          method: 'POST',
          body: {
            content: '@agent Hi Agent!',
            intent: 'conversation',
            streaming: true,
            mode: 'assistive',
            parentMessageID: '2',
          },
        },
        // Confirmations are returned as special kind of error
        response: mockEventStreamResponse(undefined, undefined, {
          type: 'error',
          errorType: 'agentUnauthorized',
          description:
            '{"authorize_url":"foo","client_id":"bar","name":"agent","avatar_url":"","slug":"agent","description":""}',
        }),
      },
    ]

    let fetchCount = 0
    mockResponses(fetches, () => fetchCount++)

    // Render thread in assistive, regardless of references match
    const {user} = render(<CopilotChat {...getCopilotChatProps()} currentTopic={undefined} apiURL="" />)

    // Open assistive panel using copilot button
    const copilotButton = await screen.findByTestId('copilot-chat-button')
    act(() => {
      copilotButton.click()
    })

    const message1 = await screen.findByTestId('message-1')
    const message2 = await screen.findByTestId('message-2')
    await within(message1).findByText('First message')
    await within(message2).findByText('First reply')

    const textArea = await screen.findByTestId('copilot-chat-input-textarea')

    await user.type(textArea, '@agent Hi Agent!')

    await user.keyboard('{enter}')

    const errorMessage = await screen.findByTestId('message-error')

    await within(errorMessage).findByTestId('agent-unauthorized-error')

    expect(fetchCount).toBe(fetches.length)
  })
})

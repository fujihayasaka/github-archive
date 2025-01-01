// This test suite tests end to end experiences of the immersive copilot chat
// Entire stack is tested, with mocked fetch responses

import type {FetchDefinition} from '@github-ui/copilot-chat/test-utils/mock-interactive'
import {mockEventStreamResponse, mockResponses} from '@github-ui/copilot-chat/test-utils/mock-interactive'
import {render} from '@github-ui/react-core/test-utils'
import {act, screen, within} from '@testing-library/react'

import {CopilotImmersive} from '../routes/CopilotImmersive'

// The import mocks have to be in test file due to jest behaviors (e.g. hoisting)
jest.mock('@github-ui/react-core/use-app-payload')
jest.mock('@github-ui/ssr-utils', () => ({
  ...jest.requireActual('@github-ui/ssr-utils'),
  // Allows safe-storage module to use local storage
  ssrSafeWindow: window,
  // Provides the current page location to useRouteThreadId
  ssrSafeLocation: {origin: 'https://github.localhost', pathname: '/copilot/c/123'},
}))

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
        // Immersive chat loads all threads
        request: {url: '/github/chat/threads?', method: 'GET'},
        response: {
          threads: [
            {
              id: '123',
              name: 'Thread Name',
              repoID: 0,
              repoOwnerID: 0,
              associatedRepoIDs: [],
              updatedAt: new Date().toString(),
            },
          ],
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
            mode: 'immersive',
            parentMessageID: '2',
          },
        },
        // Returns assistant message ID and the generated user message ID
        response: mockEventStreamResponse('Hello!', {id: '4', parentMessageID: '3', role: 'assistant'}),
      },
    ]

    let fetchCount = 0
    mockResponses(fetches, () => fetchCount++)

    const {user} = render(<CopilotImmersive />)
    // Name of the thread in the list, this also makes sure state.threads is populated
    expect(await screen.findByRole('link', {name: /Thread Name/i})).toBeVisible()

    const message1 = await screen.findByTestId('message-1')
    const message2 = await screen.findByTestId('message-2')
    expect(message1).toBeVisible()
    expect(message2).toBeVisible()
    expect(await within(message1).findByText('First message')).toBeVisible()
    expect(await within(message2).findByText('First reply')).toBeVisible()

    const textArea = await screen.findByTestId('copilot-chat-input-textarea')
    await user.type(textArea, 'Hi Copilot!')
    await user.keyboard('{enter}')

    const message3 = await screen.findByTestId('message-3')
    const message4 = await screen.findByTestId('message-4')
    expect(message3).toBeVisible()
    expect(message4).toBeVisible()
    expect(await within(message3).findByText('Hi Copilot!')).toBeVisible()
    expect(await within(message4).findByText('Hello!')).toBeVisible()

    expect(fetchCount).toBe(fetches.length)
  })

  test('Retries assistant reply', async () => {
    const fetches = [
      ...getInitialFetches(),
      {
        request: {
          url: '/github/chat/threads/123/messages?',
          method: 'POST',
          body: {
            content: 'First message', // Content is resent again to server, but is not stored and always same as the original user message
            intent: 'conversation',
            streaming: true,
            mode: 'immersive',
            parentMessageID: '1', // This actually points at the first user message
          },
        },
        // Returns assistant message ID and the generated user message ID
        response: mockEventStreamResponse('Second reply', {id: '3', parentMessageID: '1', role: 'assistant'}),
      },
    ]

    let fetchCount = 0
    mockResponses(fetches, () => fetchCount++)

    const {user} = render(<CopilotImmersive />)
    // Name of the thread in the list, this also makes sure state.threads is populated
    expect(await screen.findByRole('link', {name: /Thread Name/i})).toBeVisible()

    let message1 = await screen.findByTestId('message-1')
    const message2 = await screen.findByTestId('message-2')
    expect(message1).toBeVisible()
    expect(message2).toBeVisible()
    expect(await within(message1).findByText('First message')).toBeVisible()
    expect(await within(message2).findByText('First reply')).toBeVisible()

    const retryButton = await within(message2).findByTestId('retry-button')
    expect(retryButton).toBeVisible()

    await user.click(retryButton)

    // Wait for the new message to be rendered
    const message3 = await screen.findByTestId('message-3')
    expect(message3).toBeVisible()
    expect(await within(message3).findByText('Second reply')).toBeVisible()

    // After new message shows up the original message should still be there
    message1 = await screen.findByTestId('message-1')
    expect(message1).toBeVisible()
    expect(await within(message1).findByText('First message')).toBeVisible()

    // Hidden subthread message should be invisible
    expect(screen.queryByTestId('message-2')).toBeNull()

    expect(fetchCount).toBe(fetches.length)
  })

  test('Edits user message', async () => {
    const fetches = [
      ...getInitialFetches(),
      {
        request: {
          url: '/github/chat/threads/123/messages?',
          method: 'POST',
          body: {
            content: 'Edited first message',
            intent: 'conversation',
            streaming: true,
            mode: 'immersive',
            parentMessageID: 'root',
          },
        },
        // Returns assistant message ID and the generated user message ID
        response: mockEventStreamResponse('Reply to edited message', {
          id: '4',
          parentMessageID: '3',
          role: 'assistant',
        }),
      },
    ]

    let fetchCount = 0
    mockResponses(fetches, () => fetchCount++)

    const {user} = render(<CopilotImmersive />)
    // Name of the thread in the list, this also makes sure state.threads is populated
    expect(await screen.findByRole('link', {name: /Thread Name/i})).toBeVisible()

    const message1 = await screen.findByTestId('message-1')

    const editButton = await within(message1).findByTestId('edit-message-button')
    expect(editButton).toBeVisible()

    await user.click(editButton)

    const editTextControl = await within(message1).findByTestId('user-message-edit-box')
    expect(editTextControl).toBeVisible()
    const textArea = await within(editTextControl).findByRole('textbox')
    await user.clear(textArea)
    await user.type(textArea, 'Edited first message')
    const submitButton = await within(message1).findByTestId('user-message-edit-submit')
    await user.click(submitButton)
    expect(editTextControl).not.toBeVisible()
    expect(submitButton).not.toBeVisible()
    expect(editButton).not.toBeVisible()
    expect(textArea).not.toBeVisible()

    // Wait for the new message to be rendered
    const message4 = await screen.findByTestId('message-4')
    expect(message4).toBeVisible()
    expect(await within(message4).findByText('Reply to edited message')).toBeVisible()

    // After new message shows up the edited message should also be there
    const message3 = await screen.findByTestId('message-3')
    expect(message3).toBeVisible()
    expect(await within(message3).findByText('Edited first message')).toBeVisible()

    expect(fetchCount).toBe(fetches.length)
  })
})

describe('Rendering a thread', () => {
  test('Renders most recent subthread', async () => {
    const fetches = [
      {
        request: {url: '/github/chat/threads?', method: 'GET'},
        response: {
          threads: [
            {
              id: '123',
              name: 'Thread Name',
              repoID: 0,
              repoOwnerID: 0,
              associatedRepoIDs: [],
              updatedAt: new Date().toString(),
            },
          ],
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

    render(<CopilotImmersive />)
    // Name of the thread in the list, this also makes sure state.threads is populated
    expect(await screen.findByRole('link', {name: /Thread Name/i})).toBeVisible()

    const message1 = await screen.findByTestId('message-1')
    const message3 = await screen.findByTestId('message-3')
    expect(message1).toBeVisible()
    expect(message3).toBeVisible()
    expect(await within(message1).findByText('First message')).toBeVisible()
    expect(await within(message3).findByText('Second reply')).toBeVisible()

    // Hidden subthread message should be invisible
    expect(screen.queryByTestId('message-2')).toBeNull()

    expect(fetchCount).toBe(fetches.length)
  })

  test('Renders thread without subthread information', async () => {
    const fetches = [
      {
        request: {url: '/github/chat/threads?', method: 'GET'},
        response: {
          threads: [
            {
              id: '123',
              name: 'Thread Name',
              repoID: 0,
              repoOwnerID: 0,
              associatedRepoIDs: [],
              updatedAt: new Date().toString(),
            },
          ],
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

    render(<CopilotImmersive />)
    // Name of the thread in the list, this also makes sure state.threads is populated
    expect(await screen.findByRole('link', {name: /Thread Name/i})).toBeVisible()

    const message1 = await screen.findByTestId('message-1')
    const message2 = await screen.findByTestId('message-2')
    const message3 = await screen.findByTestId('message-3')
    const message4 = await screen.findByTestId('message-4')
    expect(message1).toBeVisible()
    expect(message2).toBeVisible()
    expect(message3).toBeVisible()
    expect(message4).toBeVisible()
    expect(await within(message1).findByText('First message')).toBeVisible()
    expect(await within(message2).findByText('First reply')).toBeVisible()
    expect(await within(message3).findByText('Second message')).toBeVisible()
    expect(await within(message4).findByText('Second reply')).toBeVisible()

    expect(fetchCount).toBe(fetches.length)
  })
})

describe('Interacting with subthreads', () => {
  test('Switching between subthreads shows only messages from that subthread', async () => {
    const fetches = [
      {
        request: {url: '/github/chat/threads?', method: 'GET'},
        response: {
          threads: [
            {
              id: '123',
              name: 'Thread Name',
              repoID: 0,
              repoOwnerID: 0,
              associatedRepoIDs: [],
              updatedAt: new Date().toString(),
            },
          ],
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

    const {user} = render(<CopilotImmersive />)
    // Name of the thread in the list, this also makes sure state.threads is populated
    expect(await screen.findByRole('link', {name: /Thread Name/i})).toBeVisible()

    let message1 = await screen.findByTestId('message-1')
    const message3 = await screen.findByTestId('message-3')
    expect(message1).toBeVisible()
    expect(message3).toBeVisible()
    expect(await within(message1).findByText('First message')).toBeVisible()
    expect(await within(message3).findByText('Second reply')).toBeVisible()

    // Hidden subthread message should be invisible
    expect(screen.queryByTestId('message-2')).toBeNull()

    const pagingComponent = await screen.findByTestId('chat-paging-component')
    expect(pagingComponent).toBeInTheDocument()

    const prevThreadButton = await screen.findByRole('button', {name: 'Previous Response'})
    await user.click(prevThreadButton)

    // First message and previously hidden message visible
    message1 = await screen.findByTestId('message-1')
    const message2 = await screen.findByTestId('message-2')
    expect(message1).toBeVisible()
    expect(message2).toBeVisible()

    // Previously visible subthreaded message now hidden
    expect(screen.queryByTestId('message-3')).toBeNull()

    expect(fetchCount).toBe(fetches.length)
  })

  test('Switching between response subthreads updates Browser files to the latest versions on that subthread', async () => {
    const fetches = [
      {
        request: {url: '/github/chat/threads?', method: 'GET'},
        response: {
          threads: [
            {
              id: '123',
              name: 'Thread Name',
              repoID: 0,
              repoOwnerID: 0,
              associatedRepoIDs: [],
              updatedAt: new Date().toString(),
            },
          ],
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
              content: 'create a very simple website with an index.html and styles.css file',
              threadID: '123',
            },
            {
              id: '2',
              parentMessageID: '1',
              role: 'assistant',
              content:
                'Sure, here are the two files for a simple website.\n\n```html name=index.html\n<!DOCTYPE html>\n<html lang="en">\n<head>\n    <meta charset="UTF-8">\n    <meta name="viewport" content="width=device-width, initial-scale=1.0">\n    <title>Simple Website</title>\n    <link rel="stylesheet" href="styles.css">\n</head>\n<body>\n    <header>\n        <h1>Welcome to My Simple Website</h1>\n    </header>\n    <main>\n        <p>This is a paragraph of text on my very simple website.</p>\n    </main>\n    <footer>\n        <p>&copy; 2025 My Simple Website</p>\n    </footer>\n</body>\n</html>\n```\n\n```css name=styles.css\nbody {\n    font-family: Arial, sans-serif;\n    margin: 0;\n    padding: 0;\n    background-color: #f4f4f4;\n    color: #333;\n}\n\nheader {\n    background-color: #4CAF50;\n    color: white;\n    padding: 1em 0;\n    text-align: center;\n}\n\nmain {\n    padding: 1em;\n}\n\nfooter {\n    background-color: #ddd;\n    color: #333;\n    text-align: center;\n    padding: 1em 0;\n    position: absolute;\n    bottom: 0;\n    width: 100%;\n}\n```',
              threadID: '123',
            },
            {
              id: '3',
              parentMessageID: '1',
              role: 'assistant',
              content:
                'Here are the files for a very simple website with an `index.html` and `styles.css` file.\n\n```html name=index.html\n<!DOCTYPE html>\n<html lang="en">\n<head>\n    <meta charset="UTF-8">\n    <meta name="viewport" content="width=device-width, initial-scale=1.0">\n    <title>Simple Website</title>\n    <link rel="stylesheet" href="styles.css">\n</head>\n<body>\n    <header>\n        <h1>Welcome to My Simple Website</h1>\n    </header>\n    <main>\n        <p>This is a simple website with an index.html and styles.css file.</p>\n    </main>\n    <footer>\n        <p>&copy; 2025 My Simple Website</p>\n    </footer>\n</body>\n</html>\n```\n\n```css name=styles.css\nbody {\n    font-family: Arial, sans-serif;\n    margin: 0;\n    padding: 0;\n    background-color: #f4f4f4;\n    color: #333;\n}\n\nheader {\n    background-color: #4CAF50;\n    color: white;\n    padding: 1em 0;\n    text-align: center;\n}\n\nmain {\n    padding: 2em;\n    text-align: center;\n}\n\nfooter {\n    background-color: #333;\n    color: white;\n    text-align: center;\n    padding: 1em 0;\n    position: fixed;\n    bottom: 0;\n    width: 100%;\n}\n```',
              threadID: '123',
            },
            {
              id: '4',
              parentMessageID: '3',
              role: 'assistant',
              content:
                'Here are the files for a very simple website with an `index.html` and `styles.css` file.\n\n```html name=index.html\n<!DOCTYPE html>\n<html lang="en">\n<head>\n    <meta charset="UTF-8">\n    <meta name="viewport" content="width=device-width, initial-scale=1.0">\n    <title>Simple Website</title>\n    <link rel="stylesheet" href="styles.css">\n</head>\n<body>\n    <header>\n        <h1>Welcome to My Simple Website</h1>\n    </header>\n    <main>\n        <p>This is a simple website with an index.html and styles.css file.</p>\n    </main>\n    <footer>\n        <p>&copy; 2025 My Simple Website</p>\n    </footer>\n</body>\n</html>\n```\n\n```css name=styles.css\nbody {\n    font-family: Arial, sans-serif;\n    margin: 0;\n    padding: 0;\n    background-color: #f4f4f4;\n    color: #333;\n}\n\nheader {\n    background-color: #4CAF50;\n    color: white;\n    padding: 1em 0;\n    text-align: center;\n}\n\nmain {\n    padding: 2em;\n    text-align: center;\n}\n\nfooter {\n    background-color: #333;\n    color: white;\n    text-align: center;\n    padding: 1em 0;\n    position: fixed;\n    bottom: 0;\n    width: 100%;\n}\n```',
              threadID: '123',
            },
          ],
        },
      },
    ]

    let fetchCount = 0
    mockResponses(fetches, () => fetchCount++)

    const {user} = render(<CopilotImmersive />)

    // Name of the thread in the list, this also makes sure state.threads is populated
    expect(await screen.findByRole('link', {name: /Thread Name/i})).toBeVisible()

    // Check correct messages are present
    expect(await screen.findByTestId('message-1')).toBeVisible()
    expect(await screen.findByTestId('message-3')).toBeVisible()
    expect(screen.queryByTestId('message-2')).toBeNull()

    // Wrapped in act() to allow ContentPreview to run concurrently with other tests
    await act(async () => {
      // Expand ContentPreview
      await user.click((await screen.findAllByTestId('chat-message-view-file-index.html'))[1]!)
      await user.click((await screen.findAllByTestId('chat-message-view-file-styles.css'))[1]!)
    })

    // Check that only the most recent file versions from the visible subthread are present:
    expect(screen.queryByTestId('content-preview-tab-file:index.html#4.3')).toBeVisible()
    expect(screen.queryByTestId('content-preview-tab-file:styles.css#4.26')).toBeVisible()
    expect(screen.queryByTestId('content-preview-tab-file:index.html#3.3')).toBeNull()
    expect(screen.queryByTestId('content-preview-tab-file:styles.css#3.26')).toBeNull()
    expect(screen.queryByTestId('content-preview-tab-file:index.html#2.3')).toBeNull()
    expect(screen.queryByTestId('content-preview-tab-file:styles.css#2.26')).toBeNull()

    // Switch to previous subthread
    await user.click(await screen.findByRole('button', {name: 'Previous Response'}))

    // Check correct messages are present
    expect(await screen.findByTestId('message-1')).toBeVisible()
    expect(await screen.findByTestId('message-2')).toBeVisible()
    expect(screen.queryByTestId('message-3')).toBeNull()

    // Check that only the most recent file versions from the new subthread are present:
    expect(screen.queryByTestId('content-preview-tab-file:index.html#2.3')).toBeVisible()
    expect(screen.queryByTestId('content-preview-tab-file:styles.css#2.26')).toBeVisible()
    expect(screen.queryByTestId('content-preview-tab-file:index.html#4.3')).toBeNull()
    expect(screen.queryByTestId('content-preview-tab-file:styles.css#4.26')).toBeNull()
    expect(screen.queryByTestId('content-preview-tab-file:index.html#3.3')).toBeNull()
    expect(screen.queryByTestId('content-preview-tab-file:styles.css#3.26')).toBeNull()

    expect(fetchCount).toBe(fetches.length)
  })

  test('Switching between subthreads updates Browser files to only show the files in the new subthread', async () => {
    const fetches = [
      {
        request: {url: '/github/chat/threads?', method: 'GET'},
        response: {
          threads: [
            {
              id: '123',
              name: 'Thread Name',
              repoID: 0,
              repoOwnerID: 0,
              associatedRepoIDs: [],
              updatedAt: new Date().toString(),
            },
          ],
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
              content: 'create a very simple website with an index.html and styles.css file',
              threadID: '123',
            },
            {
              id: '2',
              parentMessageID: '1',
              role: 'assistant',
              content:
                'Sure, here are the two files for a simple website.\n\n```html name=index.html\n<!DOCTYPE html>\n<html lang="en">\n<head>\n    <meta charset="UTF-8">\n    <meta name="viewport" content="width=device-width, initial-scale=1.0">\n    <title>Simple Website</title>\n    <link rel="stylesheet" href="styles.css">\n</head>\n<body>\n    <header>\n        <h1>Welcome to My Simple Website</h1>\n    </header>\n    <main>\n        <p>This is a paragraph of text on my very simple website.</p>\n    </main>\n    <footer>\n        <p>&copy; 2025 My Simple Website</p>\n    </footer>\n</body>\n</html>\n```\n\n```css name=styles.css\nbody {\n    font-family: Arial, sans-serif;\n    margin: 0;\n    padding: 0;\n    background-color: #f4f4f4;\n    color: #333;\n}\n\nheader {\n    background-color: #4CAF50;\n    color: white;\n    padding: 1em 0;\n    text-align: center;\n}\n\nmain {\n    padding: 1em;\n}\n\nfooter {\n    background-color: #ddd;\n    color: #333;\n    text-align: center;\n    padding: 1em 0;\n    position: absolute;\n    bottom: 0;\n    width: 100%;\n}\n```',
              threadID: '123',
            },
            {
              id: '3',
              parentMessageID: 'root',
              role: 'user',
              content: 'create a complex website with an index.html and styles.css file',
              threadID: '123',
            },
            {
              id: '4',
              parentMessageID: '3',
              role: 'assistant',
              content:
                'Here are the files for a complex website with an `index.html` and `styles.css` file.\n\n```html name=index2.html\n<!DOCTYPE html>\n<html lang="en">\n<head>\n    <meta charset="UTF-8">\n    <meta name="viewport" content="width=device-width, initial-scale=1.0">\n    <title>Simple Website</title>\n    <link rel="stylesheet" href="styles.css">\n</head>\n<body>\n    <header>\n        <h1>Welcome to My Simple Website</h1>\n    </header>\n    <main>\n        <p>This is a simple website with an index.html and styles.css file.</p>\n    </main>\n    <footer>\n        <p>&copy; 2025 My Simple Website</p>\n    </footer>\n</body>\n</html>\n```\n\n```css name=styles2.css\nbody {\n    font-family: Arial, sans-serif;\n    margin: 0;\n    padding: 0;\n    background-color: #f4f4f4;\n    color: #333;\n}\n\nheader {\n    background-color: #4CAF50;\n    color: white;\n    padding: 1em 0;\n    text-align: center;\n}\n\nmain {\n    padding: 2em;\n    text-align: center;\n}\n\nfooter {\n    background-color: #333;\n    color: white;\n    text-align: center;\n    padding: 1em 0;\n    position: fixed;\n    bottom: 0;\n    width: 100%;\n}\n```',
              threadID: '123',
            },
          ],
        },
      },
    ]

    let fetchCount = 0
    mockResponses(fetches, () => fetchCount++)

    const {user} = render(<CopilotImmersive />)

    // Name of the thread in the list, this also makes sure state.threads is populated
    expect(await screen.findByRole('link', {name: /Thread Name/i})).toBeVisible()

    // Check correct messages are present
    expect(await screen.findByTestId('message-3')).toBeVisible()
    expect(await screen.findByTestId('message-4')).toBeVisible()
    expect(screen.queryByTestId('message-1')).toBeNull()
    expect(screen.queryByTestId('message-2')).toBeNull()

    // Wrapped in act() to allow ContentPreview to run concurrently with other tests
    await act(async () => {
      // Expand ContentPreview
      await user.click(await screen.findByTestId('chat-message-view-file-index2.html'))
      await user.click(await screen.findByTestId('chat-message-view-file-styles2.css'))
    })

    // Check that only files from the visible subthread are present:
    expect(screen.queryByTestId('content-preview-tab-file:index2.html#4.3')).toBeVisible()
    expect(screen.queryByTestId('content-preview-tab-file:styles2.css#4.26')).toBeVisible()
    expect(screen.queryByTestId('content-preview-tab-file:index.html#2.3')).toBeNull()
    expect(screen.queryByTestId('content-preview-tab-file:styles.css#2.26')).toBeNull()

    // Switch to previous subthread
    await user.click(await screen.findByRole('button', {name: 'Previous Response'}))

    // Check correct messages are present
    expect(await screen.findByTestId('message-1')).toBeVisible()
    expect(await screen.findByTestId('message-2')).toBeVisible()
    expect(screen.queryByTestId('message-3')).toBeNull()
    expect(screen.queryByTestId('message-4')).toBeNull()

    // No previews should be present because there's no overlap in files from each subthread.
    expect(screen.queryByTestId('content-preview-tab-file:index.html#2.3')).toBeNull()
    expect(screen.queryByTestId('content-preview-tab-file:styles.css#2.26')).toBeNull()
    expect(screen.queryByTestId('content-preview-tab-file:index.html#4.3')).toBeNull()
    expect(screen.queryByTestId('content-preview-tab-file:styles.css#4.26')).toBeNull()

    expect(fetchCount).toBe(fetches.length)
  })

  test('Switching between subthreads updates open Browser files to the latest versions on that subthread', async () => {
    const fetches = [
      {
        request: {url: '/github/chat/threads?', method: 'GET'},
        response: {
          threads: [
            {
              id: '123',
              name: 'Thread Name',
              repoID: 0,
              repoOwnerID: 0,
              associatedRepoIDs: [],
              updatedAt: new Date().toString(),
            },
          ],
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
              content: 'create a very simple website with an index.html and styles.css file',
              threadID: '123',
            },
            {
              id: '2',
              parentMessageID: '1',
              role: 'assistant',
              content:
                'Sure, here are the two files for a simple website.\n\n```html name=index.html\n<!DOCTYPE html>\n<html lang="en">\n<head>\n    <meta charset="UTF-8">\n    <meta name="viewport" content="width=device-width, initial-scale=1.0">\n    <title>Simple Website</title>\n    <link rel="stylesheet" href="styles.css">\n</head>\n<body>\n    <header>\n        <h1>Welcome to My Simple Website</h1>\n    </header>\n    <main>\n        <p>This is a paragraph of text on my very simple website.</p>\n    </main>\n    <footer>\n        <p>&copy; 2025 My Simple Website</p>\n    </footer>\n</body>\n</html>\n```\n\n```css name=styles.css\nbody {\n    font-family: Arial, sans-serif;\n    margin: 0;\n    padding: 0;\n    background-color: #f4f4f4;\n    color: #333;\n}\n\nheader {\n    background-color: #4CAF50;\n    color: white;\n    padding: 1em 0;\n    text-align: center;\n}\n\nmain {\n    padding: 1em;\n}\n\nfooter {\n    background-color: #ddd;\n    color: #333;\n    text-align: center;\n    padding: 1em 0;\n    position: absolute;\n    bottom: 0;\n    width: 100%;\n}\n```',
              threadID: '123',
            },
            {
              id: '3',
              parentMessageID: '2',
              role: 'user',
              content: 'Can you edit the files to be shorter?',
              threadID: '123',
            },
            {
              id: '4',
              parentMessageID: '3',
              role: 'assistant',
              content:
                'Here are the files for a very simple website with an `index.html` and `styles.css` file.\n\n```html name=index.html\n<!DOCTYPE html>\n<html lang="en">\n<head>\n    <meta charset="UTF-8">\n    <meta name="viewport" content="width=device-width, initial-scale=1.0">\n    <title>Simple Website</title>\n    <link rel="stylesheet" href="styles.css">\n</head>\n<body>\n    <header>\n        <h1>Welcome to My Simple Website</h1>\n    </header>\n    <main>\n        <p>This is a simple website with an index.html and styles.css file.</p>\n    </main>\n    <footer>\n        <p>&copy; 2025 My Simple Website</p>\n    </footer>\n</body>\n</html>\n```\n\n```css name=styles.css\nbody {\n    font-family: Arial, sans-serif;\n    margin: 0;\n    padding: 0;\n    background-color: #f4f4f4;\n    color: #333;\n}\n\nheader {\n    background-color: #4CAF50;\n    color: white;\n    padding: 1em 0;\n    text-align: center;\n}\n\nmain {\n    padding: 2em;\n    text-align: center;\n}\n\nfooter {\n    background-color: #333;\n    color: white;\n    text-align: center;\n    padding: 1em 0;\n    position: fixed;\n    bottom: 0;\n    width: 100%;\n}\n```',
              threadID: '123',
            },
            {
              id: '5',
              parentMessageID: '2',
              role: 'user',
              content: 'Can you edit the files to be longer?',
              threadID: '123',
            },
            {
              id: '6',
              parentMessageID: '5',
              role: 'assistant',
              content:
                'Here are the files for a very simple website with an `index.html` and `styles.css` file.\n\n```html name=index.html\n<!DOCTYPE html>\n<html lang="en">\n<head>\n    <meta charset="UTF-8">\n    <meta name="viewport" content="width=device-width, initial-scale=1.0">\n    <title>Simple Website</title>\n    <link rel="stylesheet" href="styles.css">\n</head>\n<body>\n    <header>\n        <h1>Welcome to My Simple Website</h1>\n    </header>\n    <main>\n        <p>This is a simple website with an index.html and styles.css file.</p>\n    </main>\n    <footer>\n        <p>&copy; 2025 My Simple Website</p>\n    </footer>\n</body>\n</html>\n```\n\n```css name=styles.css\nbody {\n    font-family: Arial, sans-serif;\n    margin: 0;\n    padding: 0;\n    background-color: #f4f4f4;\n    color: #333;\n}\n\nheader {\n    background-color: #4CAF50;\n    color: white;\n    padding: 1em 0;\n    text-align: center;\n}\n\nmain {\n    padding: 2em;\n}\n\nfooter {\n    background-color: #333;\n    color: white;\n}\n```',
              threadID: '123',
            },
          ],
        },
      },
    ]

    let fetchCount = 0
    mockResponses(fetches, () => fetchCount++)

    const {user} = render(<CopilotImmersive />)

    // Name of the thread in the list, this also makes sure state.threads is populated
    expect(await screen.findByRole('link', {name: /Thread Name/i})).toBeVisible()

    // Check correct messages are present
    expect(await screen.findByTestId('message-1')).toBeVisible()
    expect(await screen.findByTestId('message-2')).toBeVisible()
    expect(await screen.findByTestId('message-5')).toBeVisible()
    expect(await screen.findByTestId('message-6')).toBeVisible()
    expect(screen.queryByTestId('message-3')).toBeNull()
    expect(screen.queryByTestId('message-4')).toBeNull()

    // Wrapped in act() to allow ContentPreview to run concurrently with other tests
    await act(async () => {
      // Expand ContentPreview
      await user.click((await screen.findAllByTestId('chat-message-view-file-index.html'))[1]!)
      await user.click((await screen.findAllByTestId('chat-message-view-file-styles.css'))[1]!)
    })

    // Check that only the most recent file versions from the visible subthread are present:
    expect(screen.queryByTestId('content-preview-tab-file:index.html#6.3')).toBeVisible()
    expect(screen.queryByTestId('content-preview-tab-file:styles.css#6.26')).toBeVisible()
    expect(screen.queryByTestId('content-preview-tab-file:index.html#4.3')).toBeNull()
    expect(screen.queryByTestId('content-preview-tab-file:styles.css#4.26')).toBeNull()
    expect(screen.queryByTestId('content-preview-tab-file:index.html#2.3')).toBeNull()
    expect(screen.queryByTestId('content-preview-tab-file:styles.css#2.26')).toBeNull()

    // Switch to previous subthread
    await user.click(await screen.findByRole('button', {name: 'Previous Response'}))

    // Check correct messages are present
    expect(await screen.findByTestId('message-1')).toBeVisible()
    expect(await screen.findByTestId('message-2')).toBeVisible()
    expect(await screen.findByTestId('message-3')).toBeVisible()
    expect(await screen.findByTestId('message-4')).toBeVisible()
    expect(screen.queryByTestId('message-5')).toBeNull()
    expect(screen.queryByTestId('message-6')).toBeNull()

    // Check that only the most recent file versions from the new subthread are present:
    expect(screen.queryByTestId('content-preview-tab-file:index.html#4.3')).toBeVisible()
    expect(screen.queryByTestId('content-preview-tab-file:styles.css#4.26')).toBeVisible()
    expect(screen.queryByTestId('content-preview-tab-file:index.html#2.3')).toBeNull()
    expect(screen.queryByTestId('content-preview-tab-file:styles.css#2.26')).toBeNull()
    expect(screen.queryByTestId('content-preview-tab-file:index.html#6.3')).toBeNull()
    expect(screen.queryByTestId('content-preview-tab-file:styles.css#6.26')).toBeNull()

    expect(fetchCount).toBe(fetches.length)
  })

  test('Switching between subthreads does not open files that were not previously open', async () => {
    const fetches = [
      {
        request: {url: '/github/chat/threads?', method: 'GET'},
        response: {
          threads: [
            {
              id: '123',
              name: 'Thread Name',
              repoID: 0,
              repoOwnerID: 0,
              associatedRepoIDs: [],
              updatedAt: new Date().toString(),
            },
          ],
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
              content: 'create a very simple website with an index.html and styles.css file',
              threadID: '123',
            },
            {
              id: '2',
              parentMessageID: '1',
              role: 'assistant',
              content:
                'Sure, here are the two files for a simple website.\n\n```html name=index.html\n<!DOCTYPE html>\n<html lang="en">\n<head>\n    <meta charset="UTF-8">\n    <meta name="viewport" content="width=device-width, initial-scale=1.0">\n    <title>Simple Website</title>\n    <link rel="stylesheet" href="styles.css">\n</head>\n<body>\n    <header>\n        <h1>Welcome to My Simple Website</h1>\n    </header>\n    <main>\n        <p>This is a paragraph of text on my very simple website.</p>\n    </main>\n    <footer>\n        <p>&copy; 2025 My Simple Website</p>\n    </footer>\n</body>\n</html>\n```\n\n```css name=styles.css\nbody {\n    font-family: Arial, sans-serif;\n    margin: 0;\n    padding: 0;\n    background-color: #f4f4f4;\n    color: #333;\n}\n\nheader {\n    background-color: #4CAF50;\n    color: white;\n    padding: 1em 0;\n    text-align: center;\n}\n\nmain {\n    padding: 1em;\n}\n\nfooter {\n    background-color: #ddd;\n    color: #333;\n    text-align: center;\n    padding: 1em 0;\n    position: absolute;\n    bottom: 0;\n    width: 100%;\n}\n```',
              threadID: '123',
            },
            {
              id: '3',
              parentMessageID: '2',
              role: 'user',
              content: 'Can you edit the files to be shorter?',
              threadID: '123',
            },
            {
              id: '4',
              parentMessageID: '3',
              role: 'assistant',
              content:
                'Here are the files for a very simple website with an `index.html` and `styles.css` file.\n\n```html name=index.html\n<!DOCTYPE html>\n<html lang="en">\n<head>\n    <meta charset="UTF-8">\n    <meta name="viewport" content="width=device-width, initial-scale=1.0">\n    <title>Simple Website</title>\n    <link rel="stylesheet" href="styles.css">\n</head>\n<body>\n    <header>\n        <h1>Welcome to My Simple Website</h1>\n    </header>\n    <main>\n        <p>This is a simple website with an index.html and styles.css file.</p>\n    </main>\n    <footer>\n        <p>&copy; 2025 My Simple Website</p>\n    </footer>\n</body>\n</html>\n```\n\n```css name=styles.css\nbody {\n    font-family: Arial, sans-serif;\n    margin: 0;\n    padding: 0;\n    background-color: #f4f4f4;\n    color: #333;\n}\n\nheader {\n    background-color: #4CAF50;\n    color: white;\n    padding: 1em 0;\n    text-align: center;\n}\n\nmain {\n    padding: 2em;\n    text-align: center;\n}\n\nfooter {\n    background-color: #333;\n    color: white;\n    text-align: center;\n    padding: 1em 0;\n    position: fixed;\n    bottom: 0;\n    width: 100%;\n}\n```',
              threadID: '123',
            },
            {
              id: '5',
              parentMessageID: '2',
              role: 'user',
              content: 'Can you edit the files to be longer?',
              threadID: '123',
            },
            {
              id: '6',
              parentMessageID: '5',
              role: 'assistant',
              content:
                'Here are the files for a very simple website with an `index.html` and `styles.css` file.\n\n```html name=index.html\n<!DOCTYPE html>\n<html lang="en">\n<head>\n    <meta charset="UTF-8">\n    <meta name="viewport" content="width=device-width, initial-scale=1.0">\n    <title>Simple Website</title>\n    <link rel="stylesheet" href="styles.css">\n</head>\n<body>\n    <header>\n        <h1>Welcome to My Simple Website</h1>\n    </header>\n    <main>\n        <p>This is a simple website with an index.html and styles.css file.</p>\n    </main>\n    <footer>\n        <p>&copy; 2025 My Simple Website</p>\n    </footer>\n</body>\n</html>\n```\n\n```css name=styles.css\nbody {\n    font-family: Arial, sans-serif;\n    margin: 0;\n    padding: 0;\n    background-color: #f4f4f4;\n    color: #333;\n}\n\nheader {\n    background-color: #4CAF50;\n    color: white;\n    padding: 1em 0;\n    text-align: center;\n}\n\nmain {\n    padding: 2em;\n}\n\nfooter {\n    background-color: #333;\n    color: white;\n}\n```',
              threadID: '123',
            },
          ],
        },
      },
    ]

    let fetchCount = 0
    mockResponses(fetches, () => fetchCount++)

    const {user} = render(<CopilotImmersive />)

    // Name of the thread in the list, this also makes sure state.threads is populated
    expect(await screen.findByRole('link', {name: /Thread Name/i})).toBeVisible()

    // Check correct messages are present
    expect(await screen.findByTestId('message-1')).toBeVisible()
    expect(await screen.findByTestId('message-2')).toBeVisible()
    expect(await screen.findByTestId('message-5')).toBeVisible()
    expect(await screen.findByTestId('message-6')).toBeVisible()
    expect(screen.queryByTestId('message-3')).toBeNull()
    expect(screen.queryByTestId('message-4')).toBeNull()

    // Expand ContentPreview
    await user.click((await screen.findAllByTestId('chat-message-view-file-index.html'))[1]!)

    // Check that only the most recent file versions from the visible subthread are present:
    expect(screen.queryByTestId('content-preview-tab-file:index.html#6.3')).toBeVisible()
    expect(screen.queryByTestId('content-preview-tab-file:styles.css#6.26')).toBeNull()
    expect(screen.queryByTestId('content-preview-tab-file:index.html#4.3')).toBeNull()
    expect(screen.queryByTestId('content-preview-tab-file:styles.css#4.26')).toBeNull()
    expect(screen.queryByTestId('content-preview-tab-file:index.html#2.3')).toBeNull()
    expect(screen.queryByTestId('content-preview-tab-file:styles.css#2.26')).toBeNull()

    // Switch to previous subthread
    await user.click(await screen.findByRole('button', {name: 'Previous Response'}))

    // Check correct messages are present
    expect(await screen.findByTestId('message-1')).toBeVisible()
    expect(await screen.findByTestId('message-2')).toBeVisible()
    expect(await screen.findByTestId('message-3')).toBeVisible()
    expect(await screen.findByTestId('message-4')).toBeVisible()
    expect(screen.queryByTestId('message-5')).toBeNull()
    expect(screen.queryByTestId('message-6')).toBeNull()

    // Check that only the most recent file versions from the new subthread are present:
    expect(screen.queryByTestId('content-preview-tab-file:index.html#4.3')).toBeVisible()
    expect(screen.queryByTestId('content-preview-tab-file:styles.css#4.26')).toBeNull()
    expect(screen.queryByTestId('content-preview-tab-file:index.html#2.3')).toBeNull()
    expect(screen.queryByTestId('content-preview-tab-file:styles.css#2.26')).toBeNull()
    expect(screen.queryByTestId('content-preview-tab-file:index.html#6.3')).toBeNull()
    expect(screen.queryByTestId('content-preview-tab-file:styles.css#6.26')).toBeNull()

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
            mode: 'immersive',
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

    const {user} = render(<CopilotImmersive />)
    // Name of the thread in the list, this also makes sure state.threads is populated
    expect(await screen.findByRole('link', {name: /Thread Name/i})).toBeVisible()

    let message1 = await screen.findByTestId('message-1')
    let message2 = await screen.findByTestId('message-2')
    expect(message1).toBeVisible()
    expect(message2).toBeVisible()
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

    // Interrupted message doesn't get retry button until we reload thread from server
    expect(within(streamingMessage).queryByTestId('retry-button')).toBeNull()

    // Allow thread to be reloaded from server
    // CopilotAnimation.tsx does internal state updates while waiting for data
    act(() => {
      jest.runAllTimers()
    })

    message1 = await screen.findByTestId('message-1')
    message2 = await screen.findByTestId('message-2')
    const message3 = await screen.findByTestId('message-3')
    const message4 = await screen.findByTestId('message-4')
    expect(message1).toBeVisible()
    expect(message2).toBeVisible()
    expect(message3).toBeVisible()
    expect(message4).toBeVisible()
    expect(await within(message1).findByText('First message')).toBeVisible()
    expect(await within(message2).findByText('First reply')).toBeVisible()
    expect(await within(message3).findByText('Second message')).toBeVisible()
    expect(await within(message4).findByText('Interrupted reply')).toBeVisible()
    // After reload, the interrupted message can be retried
    expect(within(message4).queryByTestId('retry-button')).toBeVisible()

    expect(fetchCount).toBe(fetches.length)
  })

  test('Interrupting the assistant message retry', async () => {
    const fetches = [
      ...getInitialFetches(),
      {
        request: {
          url: '/github/chat/threads/123/messages?',
          method: 'POST',
          body: {
            content: 'First message', // Content is resent again to server, but is not stored and always same as the original user message
            intent: 'conversation',
            streaming: true,
            mode: 'immersive',
            parentMessageID: '1', // This actually points at the first user message
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
              parentMessageID: '1',
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

    const {user} = render(<CopilotImmersive />)
    // Name of the thread in the list, this also makes sure state.threads is populated
    expect(await screen.findByRole('link', {name: /Thread Name/i})).toBeVisible()

    let message1 = await screen.findByTestId('message-1')
    const message2 = await screen.findByTestId('message-2')
    expect(message1).toBeVisible()
    expect(message2).toBeVisible()
    expect(await within(message1).findByText('First message')).toBeVisible()
    expect(await within(message2).findByText('First reply')).toBeVisible()

    const retryButton = await within(message2).findByTestId('retry-button')
    expect(retryButton).toBeVisible()

    await user.click(retryButton)

    const streamingMessage = await screen.findByTestId('message-streaming')
    expect(streamingMessage).toBeVisible()
    expect(await within(streamingMessage).findByText('Interrupted reply')).toBeVisible()

    const stopButton = await screen.findByTestId('copilot-chat-stop-button')
    expect(stopButton).toBeVisible()

    jest.useFakeTimers()

    await user.click(stopButton)
    expect(await within(streamingMessage).findByTestId('chat-message-interrupted')).toBeVisible()

    // Interrupted message doesn't get retry button until we reload thread from server
    expect(within(streamingMessage).queryByTestId('retry-button')).toBeNull()

    // Allow thread to be reloaded from server
    // CopilotAnimation.tsx does internal state updates while waiting for data
    act(() => {
      jest.runAllTimers()
    })

    // Wait for the new message to be rendered
    const message3 = await screen.findByTestId('message-3')
    expect(message3).toBeVisible()
    expect(await within(message3).findByText('Interrupted reply')).toBeVisible()
    // After reload, the interrupted message can be retried
    expect(within(message3).queryByTestId('retry-button')).toBeVisible()

    // After new message shows up the original message should still be there
    message1 = await screen.findByTestId('message-1')
    expect(message1).toBeVisible()
    expect(await within(message1).findByText('First message')).toBeVisible()

    // Hidden subthread message should be invisible
    expect(screen.queryByTestId('message-2')).toBeNull()

    expect(fetchCount).toBe(fetches.length)
  })

  test('Interrupting editing of user message', async () => {
    const fetches = [
      ...getInitialFetches(),
      {
        request: {
          url: '/github/chat/threads/123/messages?',
          method: 'POST',
          body: {
            content: 'Edited first message',
            intent: 'conversation',
            streaming: true,
            mode: 'immersive',
            parentMessageID: 'root',
          },
        },
        // An ongoing stream without complete payload
        response: mockEventStreamResponse('Interrupted reply to edited message'),
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
              parentMessageID: 'root',
              role: 'user',
              content: 'Edited first message',
              threadID: '123',
            },
            {
              id: '4',
              parentMessageID: '3',
              role: 'assistant',
              content: 'Interrupted reply to edited message',
              threadID: '123',
              interrupted: true,
            },
          ],
        },
      },
    ]

    let fetchCount = 0
    mockResponses(fetches, () => fetchCount++)

    const {user} = render(<CopilotImmersive />)
    // Name of the thread in the list, this also makes sure state.threads is populated
    expect(await screen.findByRole('link', {name: /Thread Name/i})).toBeVisible()

    const message1 = await screen.findByTestId('message-1')

    const editButton = await within(message1).findByTestId('edit-message-button')
    expect(editButton).toBeVisible()

    await user.click(editButton)

    const editTextControl = await within(message1).findByTestId('user-message-edit-box')
    expect(editTextControl).toBeVisible()
    const textArea = await within(editTextControl).findByRole('textbox')
    await user.clear(textArea)
    await user.type(textArea, 'Edited first message')
    const submitButton = await within(message1).findByTestId('user-message-edit-submit')
    await user.click(submitButton)
    expect(editTextControl).not.toBeVisible()
    expect(submitButton).not.toBeVisible()
    expect(editButton).not.toBeVisible()
    expect(textArea).not.toBeVisible()

    const streamingMessage = await screen.findByTestId('message-streaming')
    expect(streamingMessage).toBeVisible()
    expect(await within(streamingMessage).findByText('Interrupted reply to edited message')).toBeVisible()

    const stopButton = await screen.findByTestId('copilot-chat-stop-button')
    expect(stopButton).toBeVisible()

    jest.useFakeTimers()

    await user.click(stopButton)
    expect(await within(streamingMessage).findByTestId('chat-message-interrupted')).toBeVisible()

    // Interrupted message doesn't get retry button until we reload thread from server
    expect(within(streamingMessage).queryByTestId('retry-button')).toBeNull()

    // Allow thread to be reloaded from server
    // CopilotAnimation.tsx does internal state updates while waiting for data
    act(() => {
      jest.runAllTimers()
    })

    // Wait for the new message to be rendered
    const message4 = await screen.findByTestId('message-4')
    expect(message4).toBeVisible()
    expect(await within(message4).findByText('Interrupted reply to edited message')).toBeVisible()
    // After reload, the interrupted message can be retried
    expect(within(message4).queryByTestId('retry-button')).toBeVisible()

    // After new message shows up the edited message should also be there
    const message3 = await screen.findByTestId('message-3')
    expect(message3).toBeVisible()
    expect(await within(message3).findByText('Edited first message')).toBeVisible()

    expect(fetchCount).toBe(fetches.length)
  })
})

describe('Error handling', () => {
  test('Sending new message to an existing thread', async () => {
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
            mode: 'immersive',
            parentMessageID: '2',
          },
        },
        // First response is error
        error: true,
      },
      {
        request: {
          url: '/github/chat/threads/123/messages?',
          method: 'POST',
          body: {
            content: 'Hi Copilot!',
            intent: 'conversation',
            streaming: true,
            mode: 'immersive',
            parentMessageID: '2',
          },
        },
        // Successful response after clicking retry
        response: mockEventStreamResponse('Hello!', {id: '4', parentMessageID: '3', role: 'assistant'}),
      },
    ]

    let fetchCount = 0
    mockResponses(fetches, () => fetchCount++)

    const {user} = render(<CopilotImmersive />)
    // Name of the thread in the list, this also makes sure state.threads is populated
    expect(await screen.findByRole('link', {name: /Thread Name/i})).toBeVisible()

    const message1 = await screen.findByTestId('message-1')
    const message2 = await screen.findByTestId('message-2')
    await within(message1).findByText('First message')
    await within(message2).findByText('First reply')

    const textArea = await screen.findByTestId('copilot-chat-input-textarea')

    await user.type(textArea, 'Hi Copilot!')

    await user.keyboard('{enter}')

    const errorMessage = await screen.findByTestId('message-error')

    await within(errorMessage).findByTestId('error-message-flash')

    const retryButton = await within(errorMessage).findByTestId('retry-button')

    await act(async () => {
      retryButton.click()

      // ContentPreviewProvider finishes rendering
      await new Promise(resolve => setTimeout(resolve, 10))
    })

    await screen.findByTestId('message-3')
    await screen.findByTestId('message-4')

    expect(fetchCount).toBe(fetches.length)
  })

  test('Retrying a sucessful assistant reply', async () => {
    const fetches = [
      ...getInitialFetches(),
      {
        request: {
          url: '/github/chat/threads/123/messages?',
          method: 'POST',
          body: {
            content: 'First message', // Content is resent again to server, but is not stored and always same as the original user message
            intent: 'conversation',
            streaming: true,
            mode: 'immersive',
            parentMessageID: '1', // This actually points at the first user message
          },
        },
        // First response is error
        error: true,
      },
      {
        request: {
          url: '/github/chat/threads/123/messages?',
          method: 'POST',
          body: {
            content: 'First message', // Content is resent again to server, but is not stored and always same as the original user message
            intent: 'conversation',
            streaming: true,
            mode: 'immersive',
            parentMessageID: '1', // This actually points at the first user message
          },
        },
        // Successful response after clicking retry on the error message
        response: mockEventStreamResponse('Second reply', {id: '3', parentMessageID: '1', role: 'assistant'}),
      },
    ]

    let fetchCount = 0
    mockResponses(fetches, () => fetchCount++)

    const {user} = render(<CopilotImmersive />)
    // Name of the thread in the list, this also makes sure state.threads is populated
    expect(await screen.findByRole('link', {name: /Thread Name/i})).toBeVisible()

    const message1 = await screen.findByTestId('message-1')
    const message2 = await screen.findByTestId('message-2')
    expect(message1).toBeVisible()
    expect(message2).toBeVisible()
    expect(await within(message1).findByText('First message')).toBeVisible()
    expect(await within(message2).findByText('First reply')).toBeVisible()

    // Clicking retry on assistant message
    let retryButton = await within(message2).findByTestId('retry-button')
    expect(retryButton).toBeVisible()

    await user.click(retryButton)

    const errorMessage = await screen.findByTestId('message-error')

    await within(errorMessage).findByTestId('error-message-flash')

    retryButton = await within(errorMessage).findByTestId('retry-button')

    await act(async () => {
      // Clicking retry on error message
      retryButton.click()

      // ContentPreviewProvider finishes rendering
      await new Promise(resolve => setTimeout(resolve, 10))
    })

    await screen.findByTestId('message-1')
    await screen.findByTestId('message-3')
    expect(screen.queryByTestId('message-2')).toBeNull()

    expect(fetchCount).toBe(fetches.length)
  })

  test('Editing user message', async () => {
    const fetches = [
      ...getInitialFetches(),
      {
        request: {
          url: '/github/chat/threads/123/messages?',
          method: 'POST',
          body: {
            content: 'Edited first message',
            intent: 'conversation',
            streaming: true,
            mode: 'immersive',
            parentMessageID: 'root',
          },
        },
        // First response is error
        error: true,
      },
      {
        request: {
          url: '/github/chat/threads/123/messages?',
          method: 'POST',
          body: {
            content: 'Edited first message',
            intent: 'conversation',
            streaming: true,
            mode: 'immersive',
            parentMessageID: 'root',
          },
        },
        // Returns assistant message ID and the generated user message ID
        response: mockEventStreamResponse('Reply to edited message', {
          id: '4',
          parentMessageID: '3',
          role: 'assistant',
        }),
      },
    ]

    let fetchCount = 0
    mockResponses(fetches, () => fetchCount++)

    const {user} = render(<CopilotImmersive />)
    // Name of the thread in the list, this also makes sure state.threads is populated
    expect(await screen.findByRole('link', {name: /Thread Name/i})).toBeVisible()

    const message1 = await screen.findByTestId('message-1')

    const editButton = await within(message1).findByTestId('edit-message-button')
    expect(editButton).toBeVisible()

    await user.click(editButton)

    const editTextControl = await within(message1).findByTestId('user-message-edit-box')
    expect(editTextControl).toBeVisible()
    const textArea = await within(editTextControl).findByRole('textbox')
    await user.clear(textArea)
    await user.type(textArea, 'Edited first message')
    const submitButton = await within(message1).findByTestId('user-message-edit-submit')
    await user.click(submitButton)
    expect(editTextControl).not.toBeVisible()
    expect(submitButton).not.toBeVisible()
    expect(editButton).not.toBeVisible()
    expect(textArea).not.toBeVisible()

    const errorMessage = await screen.findByTestId('message-error')

    await within(errorMessage).findByTestId('error-message-flash')

    const retryButton = await within(errorMessage).findByTestId('retry-button')

    await act(async () => {
      // Clicking retry on error message
      retryButton.click()

      // ContentPreviewProvider finishes rendering
      await new Promise(resolve => setTimeout(resolve, 10))
    })

    // Wait for the new message to be rendered
    const message4 = await screen.findByTestId('message-4')
    expect(message4).toBeVisible()
    expect(await within(message4).findByText('Reply to edited message')).toBeVisible()

    // After new message shows up the edited message should also be there
    const message3 = await screen.findByTestId('message-3')
    expect(message3).toBeVisible()
    expect(await within(message3).findByText('Edited first message')).toBeVisible()

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
            mode: 'immersive',
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

    const {user} = render(<CopilotImmersive />)
    // Name of the thread in the list, this also makes sure state.threads is populated
    expect(await screen.findByRole('link', {name: /Thread Name/i})).toBeVisible()

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
  test('Rendering when editing user message', async () => {
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
            mode: 'immersive',
            parentMessageID: 'root', // Editing the first message
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

    const {user} = render(<CopilotImmersive />)
    // Name of the thread in the list, this also makes sure state.threads is populated
    expect(await screen.findByRole('link', {name: /Thread Name/i})).toBeVisible()

    const message1 = await screen.findByTestId('message-1')

    const editButton = await within(message1).findByTestId('edit-message-button')

    await user.click(editButton)

    const editTextControl = await within(message1).findByTestId('user-message-edit-box')
    const textArea = await within(editTextControl).findByRole('textbox')
    await user.clear(textArea)
    await user.type(textArea, '@agent Hi Agent!')
    const submitButton = await within(message1).findByTestId('user-message-edit-submit')
    await user.click(submitButton)

    const errorMessage = await screen.findByTestId('message-error')

    await within(errorMessage).findByTestId('agent-unauthorized-error')

    expect(fetchCount).toBe(fetches.length)
  })
})

import type {CopilotChatThread} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {getCustomCopilotMock} from '@github-ui/custom-copilots/test-utils/mock-data'
import {mockFetch} from '@github-ui/mock-fetch'
import {render} from '@github-ui/react-core/test-utils'
import {screen, waitFor} from '@testing-library/react'

import {CopilotImmersive} from '../routes/CopilotImmersive'
import {getCopilotImmersiveAppPayload} from '../test-utils/mock-data'

const mockFetchCustomCopilot = jest.fn()
const mockDispatch = jest.fn()
const mockMaxMessagesReached = jest.fn(() => false)

jest.spyOn(copilotFeatureFlags, 'customCopilots', 'get').mockReturnValue(true)

jest.mock('@github-ui/copilot-chat/CopilotChatManagerContext', () => {
  return {
    ...jest.requireActual('@github-ui/copilot-chat/CopilotChatManagerContext'),
    useChatManager: () => {
      return {
        fetchCustomCopilot: mockFetchCustomCopilot,
        dispatch: mockDispatch,
        maxMessagesReached: mockMaxMessagesReached,
        fetchModels: jest.fn(),
        getSelectedThread: jest.fn(),
        getSystemPrompt: jest.fn(),
        clearCurrentReferences: jest.fn(),
        clearSuggestions: jest.fn(),
        fetchThreads: jest.fn(),
        fetchMessages: jest.fn(),
        cancelThreadReload: jest.fn(),
        sortThreads: jest.fn((threads: Map<string, CopilotChatThread>): CopilotChatThread[] =>
          Array.from(threads.values()),
        ),
        setTopRepositoryTopics: jest.fn(),
      }
    },
  }
})

beforeEach(() => {
  jest.clearAllMocks()
  window.localStorage.clear()
  // We utilize service workers to fuzy search references in Copilot Chat
  // when they are not available we show a warning to the user.
  // Workers are not available in JSDOM so we need to mock the console.warn.
  jest.spyOn(console, 'warn').mockImplementation()
})

test('Fetches customCopilots and adds them to the chat state', async () => {
  const appPayload = getCopilotImmersiveAppPayload()
  appPayload.copilotChatSettingEnabled = true
  const testCustomCopilot = getCustomCopilotMock()

  mockFetch.mockRouteOnce('/github-copilot/chat/custom_copilots', [testCustomCopilot])

  render(<CopilotImmersive />, {
    appPayload,
  })
  await waitFor(() => {
    expect(mockDispatch).toHaveBeenCalledWith({
      type: 'SET_CUSTOM_COPILOTS',
      customCopilots: [testCustomCopilot],
    })
  })
  expect(mockFetch.fetch).toHaveBeenCalledWith('/github-copilot/chat/custom_copilots', expect.anything())

  await expect(screen.findByTestId('chat-layout')).resolves.toBeInTheDocument()
})

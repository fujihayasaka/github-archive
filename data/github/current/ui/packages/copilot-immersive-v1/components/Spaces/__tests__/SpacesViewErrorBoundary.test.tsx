import {getCopilotChatProviderProps, getDefaultReducerState} from '@github-ui/copilot-chat/test-utils/mock-data'
import type {CopilotChatState} from '@github-ui/copilot-chat/utils/copilot-chat-reducer'
import type {CustomCopilot} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {ChatStateProvider, CopilotChatProvider} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {getCustomCopilotMock} from '@github-ui/custom-copilots/test-utils/mock-data'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {Wrapper as ContextPreviewTestWrapper} from '../../../markdown-extensions/issue-blocks/test-utils/Wrapper'
import {SpacesListPage} from '../SpacesListPage'

// Mock hydro analytics
jest.mock('@github-ui/hydro-analytics', () => ({
  sendEvent: jest.fn(),
}))

// Mock SpacesCard component to throw an error
jest.mock('../SpacesCard', () => ({
  SpacesCard: () => {
    throw new Error('Test error from SpacesCard')
  },
}))

// Helper function to create a wrapper component with state management
function createTestWrapper(initialState: CopilotChatState, copilotSpaces?: CustomCopilot[]) {
  return function TestWrapper() {
    return (
      <ContextPreviewTestWrapper>
        <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="2" mode="immersive">
          <ChatStateProvider state={initialState}>
            <SpacesListPage copilotSpaces={copilotSpaces} />
          </ChatStateProvider>
        </CopilotChatProvider>
      </ContextPreviewTestWrapper>
    )
  }
}

// Sample data for tests
const mockCopilotSpaces: CustomCopilot[] = [
  getCustomCopilotMock({
    id: 1,
    name: 'Test Space 1',
    description: 'First test space',
  }),
]

describe('SpacesView ErrorBoundary', () => {
  // Silence React's error boundary logs since we're deliberately testing error cases
  // eslint-disable-next-line no-console
  const originalConsoleError = console.error

  beforeEach(() => {
    jest.clearAllMocks()
    // Mock console.error to prevent test failures from expected error logs
    // eslint-disable-next-line no-console
    console.error = jest.fn()
  })

  afterEach(() => {
    // Restore original console.error after tests
    // eslint-disable-next-line no-console
    console.error = originalConsoleError
  })

  test('renders the ErrorFallback component when SpacesCard throws an error', () => {
    const initialState = {
      ...getDefaultReducerState('2', undefined, 'immersive'),
      ssoOrganizations: [],
    }

    const TestWrapper = createTestWrapper(initialState, mockCopilotSpaces)
    render(<TestWrapper />)

    // Verify the ErrorFallback is shown
    expect(screen.getByText('Something went wrong')).toBeInTheDocument()
    expect(screen.getByText(/Spaces is temporarily unavailable/)).toBeInTheDocument()
  })
})

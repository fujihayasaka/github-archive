import {getCopilotChatProviderProps, getDefaultReducerState} from '@github-ui/copilot-chat/test-utils/mock-data'
import type {CopilotChatManager} from '@github-ui/copilot-chat/utils/copilot-chat-manager'
import type {CopilotChatAction, CopilotChatState} from '@github-ui/copilot-chat/utils/copilot-chat-reducer'
import type {CopilotChatThread, CustomCopilot} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {ChatStateProvider, CopilotChatProvider} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {getCustomCopilotMock} from '@github-ui/custom-copilots/test-utils/mock-data'
import {customCopilotQueryKey} from '@github-ui/custom-copilots/utils/fetch'
import {mockFetch} from '@github-ui/mock-fetch'
import {getQueryClient} from '@github-ui/react-core/query-client'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {createRelayMockEnvironment} from '@github-ui/relay-test-utils/RelayMockEnvironment'
import {screen, waitFor} from '@testing-library/react'
import React from 'react'
import {RelayEnvironmentProvider} from 'react-relay'

import {SpaceDetailsPage, type SpaceDetailsPageProps} from '../SpaceDetailsPage'

const userEvent = setupUserEvent()

const mockFetchCustomCopilot = jest.fn()
const mockDispatch = jest.fn()
const mockMaxMessagesReached = jest.fn(() => false)
const mockClearCurrentReferences = jest.fn()

const chatManager = jest.createMockFromModule<CopilotChatManager>('@github-ui/copilot-chat/utils/copilot-chat-manager')
chatManager.sortThreads = jest.fn((threads: Map<string, CopilotChatThread>): CopilotChatThread[] =>
  Array.from(threads.values()),
)

jest.mock('@github-ui/copilot-chat/CopilotChatManagerContext', () => {
  return {
    ...jest.requireActual('@github-ui/copilot-chat/CopilotChatManagerContext'),
    useChatManager: () => {
      return {
        fetchCustomCopilot: mockFetchCustomCopilot,
        dispatch: mockDispatch,
        maxMessagesReached: mockMaxMessagesReached,
        getSelectedThread: jest.fn(),
        clearCurrentReferences: mockClearCurrentReferences,
        cancelThreadReload: jest.fn(),
        sortThreads: jest.fn((threads: Map<string, CopilotChatThread>): CopilotChatThread[] =>
          Array.from(threads.values()),
        ),
        setTopRepositoryTopics: jest.fn(),
        fetchModels: jest.fn(),
      }
    },
  }
})

// Default props used across tests
const defaultProps = {
  selectedThreadID: '123',
  textAreaRef: React.createRef<HTMLTextAreaElement>(),
  customCopilotId: {id: 1, owner: 'test-owner'},
  onChatSubmit: jest.fn(),
}

// Helper function to create a wrapper component with state management
function createTestWrapper(initialState: CopilotChatState, props: SpaceDetailsPageProps) {
  return function TestWrapper() {
    const [state, setState] = React.useState<CopilotChatState>(initialState)

    const {environment} = createRelayMockEnvironment()

    React.useEffect(() => {
      mockDispatch.mockImplementation((action: CopilotChatAction) => {
        if (action.type === 'SET_CUSTOM_COPILOT') {
          setState({
            ...state,
            customCopilots: [action.customCopilot],
          })
        }
      })
    }, [state])

    return (
      <RelayEnvironmentProvider environment={environment}>
        <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="2" mode="immersive">
          <ChatStateProvider state={state}>
            <SpaceDetailsPage {...props} />
          </ChatStateProvider>
        </CopilotChatProvider>
      </RelayEnvironmentProvider>
    )
  }
}

describe('SpaceDetails', () => {
  beforeEach(() => {
    mockFetchCustomCopilot.mockReset()
    mockDispatch.mockReset()
    mockMaxMessagesReached.mockReset()
  })

  test('renders space when currentSpace is available', () => {
    // Mock a successful custom copilot fetch

    const newId = 5
    const oldId = 42
    const customCopilot = getCustomCopilotMock({id: newId, oldId})

    const queryClient = getQueryClient()
    queryClient.setQueryData(customCopilotQueryKey({id: newId, owner: 'test-owner'}), customCopilot)

    const initialState = {
      ...getDefaultReducerState('2', undefined, 'immersive'),
      customCopilots: [customCopilot],
      threads: new Map([
        [
          '123',
          {
            id: '123',
            customCopilotID: newId, // this is the CustomCopilot number
            customCopilotOwner: 'test-owner',
            messages: [],
            name: 'New Thread',
            createdAt: '2023-01-01T00:00:00Z',
            updatedAt: '2023-01-01T00:00:00Z',
          } as CopilotChatThread,
        ],
        [
          '456',
          {
            id: '456',
            customCopilotID: oldId, // this is a legacy thread, CustomCopilot Id
            customCopilotOwner: undefined,
            messages: [],
            name: 'Old Thread',
            createdAt: '2023-01-01T00:00:00Z',
            updatedAt: '2023-01-01T00:00:00Z',
          } as CopilotChatThread,
        ],
      ]),
    }

    const testProps = {...defaultProps, customCopilotId: {id: newId, oldId, owner: 'test-owner'}}
    const TestWrapper = createTestWrapper(initialState, testProps)
    render(<TestWrapper />)

    // Verify we can see the space name and description
    expect(screen.getByText('Test Space 5')).toBeInTheDocument()
    expect(screen.getByText('Test space 5 description')).toBeInTheDocument()
    // We see both old and new threads
    expect(screen.getByText('Old Thread')).toBeInTheDocument()
    expect(screen.getByText('New Thread')).toBeInTheDocument()

    expect(mockClearCurrentReferences).toHaveBeenCalled()
  })

  test('renders loading state while waiting for space data to be fetched', () => {
    // Don't mock anything to simulate loading

    const initialState = {
      ...getDefaultReducerState('2', undefined, 'immersive'),
      customCopilots: [],
    }

    const TestWrapper = createTestWrapper(initialState, defaultProps)
    render(<TestWrapper />)

    // Verify loading state is rendered
    expect(screen.getByTestId('conversation-loader')).toBeInTheDocument()
  })

  test('updates state when fetchCustomCopilot returns space data', async () => {
    const spaceData = getCustomCopilotMock()

    const queryClient = getQueryClient()
    queryClient.setQueryData(customCopilotQueryKey(spaceData), spaceData)
    const initialState = {
      ...getDefaultReducerState('2', undefined, 'immersive'),
      customCopilots: [],
    }

    const TestWrapper = createTestWrapper(initialState, defaultProps)
    render(<TestWrapper />)

    // Verify the dispatch was called with the SET_CUSTOM_COPILOT action
    await waitFor(() => {
      expect(mockDispatch).toHaveBeenCalledWith({
        type: 'SET_CUSTOM_COPILOT',
        customCopilot: spaceData,
      })
    })
    // Verify we can see the space name and description
    await screen.findByText('Test Space 1')
    await screen.findByText('Test space 1 description')
  })

  test('renders reference size exceeded banner if reference content size exceeds limit', async () => {
    const newId = 5
    const oldId = 42
    const resources = [
      {
        id: '2',
        databaseId: 2,
        repositoryId: 5,
        nwo: 'github/github',
        filePath: 'docs/README.md',
        sizePercentage: 2,
        fileExists: true,
        markedForDestroy: false,
        type: 'github_file' as const,
        commitish: 'main',
      },
    ]
    const customCopilot = getCustomCopilotMock({id: newId, oldId, resources, sizePercentage: 101})
    const queryClient = getQueryClient()
    queryClient.setQueryData(customCopilotQueryKey(customCopilot), customCopilot)

    const initialState = {
      ...getDefaultReducerState('2', undefined, 'immersive'),
      customCopilots: [customCopilot],
    }

    const testProps = {...defaultProps, customCopilotId: {id: newId, oldId, owner: 'test-owner'}}
    const TestWrapper = createTestWrapper(initialState, testProps)
    render(<TestWrapper />)

    expect(
      await screen.findByText("You've exceeded the size limit for this space. Remove some references to continue."),
    ).toBeInTheDocument()
    expect(screen.getByTestId('copilot-chat-input-textarea')).toBeDisabled()
  })

  describe('starred', () => {
    let customCopilot: CustomCopilot
    let TestWrapper: () => JSX.Element

    beforeEach(() => {
      mockFetch.clear()
      customCopilot = getCustomCopilotMock()

      const queryClient = getQueryClient()
      queryClient.setQueryData(customCopilotQueryKey(customCopilot), customCopilot)
      const initialState = {
        ...getDefaultReducerState('2', undefined, 'immersive'),
        customCopilots: [customCopilot],
      }

      TestWrapper = createTestWrapper(initialState, defaultProps)
    })

    test('does not show starred section if space has zero starred users', () => {
      customCopilot.starredUsers = []
      render(<TestWrapper />)
      expect(screen.queryByText('Starred by')).not.toBeInTheDocument()
    })

    test('show starred section if space has starred users', () => {
      customCopilot.starredUsers = [{login: 'foo', avatarUrl: 'https://github.com/monalisa.png'}]
      render(<TestWrapper />)

      expect(screen.getByText('Starred by')).toBeInTheDocument()
    })

    test('show star button even if space is editable', () => {
      customCopilot.editable = true
      customCopilot.starred = false
      render(<TestWrapper />)

      expect(screen.getByText('Star')).toBeInTheDocument()
    })

    test('starred if space is unstarred', async () => {
      customCopilot.editable = false
      customCopilot.starred = false
      render(<TestWrapper />)

      const starButton = screen.getByText('Star')
      expect(starButton).toBeInTheDocument()
      await userEvent.click(starButton)

      expect(mockFetch.fetch).toHaveBeenCalledWith(
        `/copilot/spaces/${customCopilot.owner}/${customCopilot.id}/stars`,
        expect.objectContaining({
          method: 'POST',
        }),
      )

      // Verify the dispatch was called with the SET_CUSTOM_COPILOT action
      await waitFor(() => {
        expect(mockDispatch).toHaveBeenCalledWith({
          type: 'SET_CUSTOM_COPILOT',
          customCopilot,
        })
      })
    })

    test('unstarred if space is starred', async () => {
      customCopilot.editable = false
      customCopilot.starred = true
      render(<TestWrapper />)

      const starredButton = screen.getByText('Starred')
      expect(starredButton).toBeInTheDocument()
      await userEvent.click(starredButton)

      expect(mockFetch.fetch).toHaveBeenCalledWith(
        `/copilot/spaces/${customCopilot.owner}/${customCopilot.id}/stars`,
        expect.objectContaining({
          method: 'DELETE',
        }),
      )

      // Verify the dispatch was called with the SET_CUSTOM_COPILOT action
      await waitFor(() => {
        expect(mockDispatch).toHaveBeenCalledWith({
          type: 'SET_CUSTOM_COPILOT',
          customCopilot,
        })
      })
    })

    test('does not star if error', async () => {
      customCopilot.editable = false
      customCopilot.starred = false
      render(<TestWrapper />)

      mockFetch.mockRoute(`/copilot/spaces/${customCopilot.owner}/${customCopilot.id}/stars`, undefined, {
        ok: false,
      })

      mockDispatch.mockClear()
      await userEvent.click(screen.getByText('Star'))

      expect(mockFetch.fetch).toHaveBeenCalledWith(
        `/copilot/spaces/${customCopilot.owner}/${customCopilot.id}/stars`,
        expect.objectContaining({
          method: 'POST',
        }),
      )

      expect(screen.getByText('Star')).toBeInTheDocument()

      // Verify the dispatch was not called with the SET_CUSTOM_COPILOT action
      await waitFor(() => {
        expect(mockDispatch).not.toHaveBeenCalledWith({
          type: 'SET_CUSTOM_COPILOT',
          customCopilot,
        })
      })
    })
  })

  test('clears current references when component unmounts', async () => {
    // Mock a successful custom copilot fetch
    const customCopilot = getCustomCopilotMock()
    const queryClient = getQueryClient()
    queryClient.setQueryData(customCopilotQueryKey(defaultProps.customCopilotId), customCopilot)

    const initialState = {
      ...getDefaultReducerState('2', undefined, 'immersive'),
      ssoOrganizations: [],
      customCopilots: [customCopilot],
    }

    const TestWrapper = createTestWrapper(initialState, defaultProps)
    const {unmount} = render(<TestWrapper />)

    // Wait for component to mount and load
    await waitFor(() => {
      expect(screen.getByText(customCopilot.name)).toBeInTheDocument()
    })

    // Reset the mock to clear any calls made during component setup
    mockClearCurrentReferences.mockClear()

    // Unmount the component to trigger cleanup
    unmount()

    // Verify that manager.clearCurrentReferences() was called during cleanup
    expect(mockClearCurrentReferences).toHaveBeenCalledWith()
  })

  test('does not clear references when component unmounts during message submission', async () => {
    // Mock a successful custom copilot fetch
    const customCopilot = getCustomCopilotMock({id: 5})
    const queryClient = getQueryClient()
    queryClient.setQueryData(customCopilotQueryKey(defaultProps.customCopilotId), customCopilot)

    // Create a delayed onChatSubmit function to simulate async submission
    let resolveSubmit: () => void
    const mockOnChatSubmit = jest.fn().mockImplementation(() => {
      return new Promise<void>(resolve => {
        resolveSubmit = resolve
      })
    })

    const initialState = {
      ...getDefaultReducerState('2', undefined, 'immersive'),
      ssoOrganizations: [],
    }

    const propsWithMockSubmit = {...defaultProps, onChatSubmit: mockOnChatSubmit}
    const TestWrapper = createTestWrapper(initialState, propsWithMockSubmit)
    const {unmount} = render(<TestWrapper />)

    // Wait for component to mount and load
    await waitFor(() => {
      expect(screen.getByText(customCopilot.name)).toBeInTheDocument()
    })

    // Get the chat input and simulate a message submission
    const chatInput = screen.getByTestId('copilot-chat-input-textarea')
    await userEvent.type(chatInput, 'test message')
    await userEvent.keyboard('{Enter}')

    // Verify that onChatSubmit was called
    await waitFor(() => {
      expect(mockOnChatSubmit).toHaveBeenCalledWith('test message')
    })

    // Reset the mock to clear any calls made during component setup
    mockClearCurrentReferences.mockClear()

    // Unmount the component while the message submission is still in progress
    unmount()

    // Verify that manager.clearCurrentReferences() was NOT called during cleanup
    // because the submission is still in progress
    expect(mockClearCurrentReferences).not.toHaveBeenCalled()

    // Complete the submission
    resolveSubmit!()
  })
})

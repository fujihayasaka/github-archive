import {useNavigate} from '@github-ui/use-navigate'
import {act, renderHook} from '@testing-library/react'

import {type WorkbenchStoreProps, WorkbenchStoreWrapper} from '../../__tests__/WorkbenchStoreWrapper'
import {useContentFilter} from '../../contexts/ContentFilterContext'
import {type FilesContextData, useFilesContext} from '../../contexts/FilesContext'
import {useIterationHistory} from '../../contexts/IterationHistoryContext'
import {useUserPromptContext} from '../../contexts/UserPromptContext'
import {useWorkbenchContext} from '../../contexts/WorkbenchContext'
import {useWorkbenchEditorAppContext} from '../../contexts/WorkbenchEditorAppContext'
import type {BlobService} from '../../utilities/blob-service'
import type {FileStreamEvent} from '../../utilities/generate-iteration'
import {FileStreamEventType, generateIteration} from '../../utilities/generate-iteration'
import {Service} from '../../utilities/workbench-store-reducer'
import {useFetchFromCodespaceApi} from '../use-fetch-from-codespace-api'
import {useWorkbench} from '../use-workbench'

// Mock dependencies
jest.mock('@github-ui/use-navigate', () => ({
  useNavigate: jest.fn(),
}))

jest.mock('../../telemetry/use-analytics', () => ({
  useAnalytics: jest.fn().mockReturnValue(jest.fn()),
}))

// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: jest.fn().mockResolvedValue({}),
}))

jest.mock('@github-ui/react-core/use-route-payload', () => ({
  useRoutePayload: jest.fn().mockReturnValue({
    workbench: {id: 'test-id'},
    copilot: {ssoOrganizations: [], apiURL: 'test-url', currentTopic: 'test-topic'},
    isNewFilePage: false,
  }),
}))

jest.mock('../../contexts/FilesContext', () => ({
  useFilesContext: jest.fn().mockReturnValue({
    addFile: jest.fn(),
    editFile: jest.fn(),
    getCurrentFileContent: jest.fn().mockReturnValue({content: 'mock content'}),
    getFileStatuses: jest.fn().mockReturnValue({}),
  }),
}))

jest.mock('../../contexts/FileSyncerContext', () => ({
  useFileSyncerContext: jest.fn().mockReturnValue({
    fileSyncerStarted: false,
    forceFileTreeRefresh: jest.fn(),
    notifyEdited: jest.fn(),
    getFileSyncerV2: jest.fn().mockReturnValue(null),
    fileContentsRef: {current: null},
  }),
}))

jest.mock('../../contexts/IterationHistoryContext')

jest.mock('../../contexts/ContentFilterContext')

jest.mock('../../contexts/ServerEventsContext', () => ({
  useServerEvents: jest.fn().mockReturnValue({
    serverEvents: [],
    connectionStatus: 'disconnected',
    fetchFromCodespaceApi: jest.fn().mockReturnValue(Promise.resolve({})),
  }),
}))

jest.mock('../../hooks/use-fetch-from-codespace-api', () => ({
  useFetchFromCodespaceApi: jest.fn().mockReturnValue({fetchFromCodespaceApi: jest.fn()}),
}))

jest.mock('../../contexts/WorkbenchContext')

jest.mock('../../utilities/urls', () => ({
  sparkFileUrl: jest.fn(() => '/mock-url'),
}))

jest.mock('../use-stable-callback', () => ({
  useStableCallback: jest.fn(cb => cb),
}))

jest.mock('../../utilities/retry-with-backoff', () => ({
  createRetryWithBackoff: jest.fn(fn => fn),
}))

// Mock WorkbenchEditorAppContext
jest.mock('../../contexts/WorkbenchEditorAppContext', () => ({
  useWorkbenchEditorAppContext: jest.fn().mockReturnValue({}),
}))

jest.mock('../../contexts/UserPromptContext')

// Mock generateIteration
jest.mock('../../utilities/generate-iteration', () => ({
  FileStreamEventType: {
    NEW_FILE: 'NEW_FILE',
    FILE_CONTENT_CHUNK: 'FILE_CONTENT_CHUNK',
    SELF_REFINEMENT: 'SELF_REFINEMENT',
    END_FILE: 'END_FILE',
    ERROR: 'ERROR',
    COMPLETE: 'COMPLETE',
    CONTENT_FILTERED: 'CONTENT_FILTERED',
    PROMPT_FILTERED: 'PROMPT_FILTERED',
    FILTER_EXPLANATION_CHUNK: 'FILTER_EXPLANATION_CHUNK',
    FILTER_SUGGESTION: 'FILTER_SUGGESTION',
  },
  generateIteration: jest.fn().mockResolvedValue([]),
}))

type renderUseWorkbenchProps = {
  workbenchStore?: WorkbenchStoreProps
}
function renderUseWorkbench(props: renderUseWorkbenchProps = {}) {
  return renderHook(() => useWorkbench(), {wrapper: WorkbenchStoreWrapper(props.workbenchStore ?? {})})
}

describe('useWorkbench', () => {
  const mockNavigate = jest.fn()

  let setFilteredCategories: jest.Mock
  let setIsFilteredModalOpen: jest.Mock
  let updateFilterExplanationContent: jest.Mock
  let setCurrentRefinement: jest.Mock
  let setPreviousRefinements: jest.Mock
  let clearFilterExplanationContent: jest.Mock
  let setIsFetching: jest.Mock
  let setIsOptimisticLoading: jest.Mock
  let setIsLoadingFromModel: jest.Mock
  let setPromptText: jest.Mock
  beforeEach(() => {
    jest.clearAllMocks()
    ;(useNavigate as jest.Mock).mockReturnValue(mockNavigate)

    setIsLoadingFromModel = jest.fn()
    setIsFetching = jest.fn()
    setIsOptimisticLoading = jest.fn()
    ;(useWorkbenchContext as jest.Mock).mockReturnValue({
      setIsFetching,
      setIsOptimisticLoading,
      setIsLoadingFromModel,
      initialPromptSubmitted: {current: false},
      iterationStartTime: null,
      setIterationStartTime: jest.fn(),
    })
    setCurrentRefinement = jest.fn()
    setPreviousRefinements = jest.fn()
    ;(useIterationHistory as jest.Mock).mockReturnValue({
      previousRefinements: [],
      setPreviousRefinements,
      setCurrentRefinement,
      currentRefinementId: '',
    })

    setFilteredCategories = jest.fn()
    setIsFilteredModalOpen = jest.fn()
    updateFilterExplanationContent = jest.fn()
    clearFilterExplanationContent = jest.fn()
    jest.mocked(useContentFilter as jest.Mock).mockReturnValue({
      setFilteredCategories,
      setIsFilteredModalOpen,
      filterExplanationContent: null,
      clearFilterExplanationContent,
      updateFilterExplanationContent,
    })

    setPromptText = jest.fn()
    jest.mocked(useUserPromptContext).mockReturnValue({
      setPromptText,
      setPromptImage: jest.fn(),
      clearImageAttachment: jest.fn(),
    } as unknown as ReturnType<typeof useUserPromptContext>)
  })

  it('handles file removed from queue during blob fetch operation', async () => {
    // Mock the blob service with a delayed promise
    const mockBlobService = {
      getBlob: jest.fn().mockImplementation(
        () =>
          new Promise(resolve => {
            // Delay to simulate network request
            setTimeout(() => {
              resolve({ok: true, payload: {blobContents: 'original content'}})
            }, 100)
          }),
      ),
    } as unknown as BlobService

    // Mock the editFile function to track calls
    const mockEditFile = jest.fn()

    // Set up the context mock with our controlled implementations
    jest.mocked(useFilesContext).mockReturnValue({
      addFile: jest.fn(),
      editFile: mockEditFile,
      getCurrentFileContent: jest.fn().mockReturnValue({content: 'mock content'}),
      getFileStatuses: jest.fn().mockReturnValue({}), // Add mock implementation for getFileStatuses
    } as unknown as FilesContextData)

    jest.mocked(useWorkbenchEditorAppContext).mockReturnValue({
      blobService: mockBlobService,
    })

    // Set up timers for controlling async operations
    jest.useFakeTimers()

    const {result} = renderUseWorkbench()

    let onEvent: ((event: FileStreamEvent) => void) | undefined

      // Mock generateIteration to capture the onEvent callback
    ;(generateIteration as jest.Mock).mockImplementationOnce(
      ({onEvent: callback}: {onEvent: (event: FileStreamEvent) => void}) => {
        onEvent = callback
        return Promise.resolve([])
      },
    )

    // Start the prompt submission to initialize the internal state
    await act(async () => {
      await result.current.submitPrompt('test prompt', 'generate')
    })

    // Simulate file content events to create a queue for processing
    act(() => {
      if (onEvent) {
        // Add a new file
        onEvent({
          type: FileStreamEventType.NEW_FILE,
          fileName: 'test.js',
        })

        // Add content to queue
        onEvent({
          type: FileStreamEventType.FILE_CONTENT_CHUNK,
          fileName: 'test.js',
          chunk: 'console.log("test");\n',
        })
      }
    })

    // Before the blob service resolves, simulate cancellation which clears queues
    act(() => {
      result.current.cancelPrompt()
    })

    // Fast-forward time to let async operations complete
    jest.advanceTimersByTime(150)

    // Ensure all promises resolve
    await act(async () => {
      await Promise.resolve()
    })

    // Verify editFile wasn't called after queues were cleared
    // This is the key check - if our guard clause is working, editFile won't be called
    // after the queue is cleared, even though the blob service resolved
    expect(mockEditFile).not.toHaveBeenCalledWith(
      expect.objectContaining({
        filePath: 'test.js',
        newFileContent: 'console.log("test");\n',
      }),
    )

    // Clean up timers
    jest.useRealTimers()
  })

  it('properly cleans up previous refinements when canceling a prompt', async () => {
    const {result} = renderUseWorkbench()

    // Set up mock for blobService
    const mockBlobService = {
      getBlob: jest.fn().mockResolvedValue({ok: true, payload: {blobContents: ''}}),
    } as unknown as BlobService

    jest.mocked(useWorkbenchEditorAppContext).mockReturnValue({
      blobService: mockBlobService,
    })

    // Mock the file status for cleanup
    const mockFileStatuses = {'test.js': {}}
    jest.mocked(useFilesContext).mockReturnValue({
      addFile: jest.fn(),
      editFile: jest.fn(),
      getCurrentFileContent: jest.fn().mockReturnValue({content: 'mock content'}),
      getFileStatuses: jest.fn().mockReturnValue(mockFileStatuses),
      deleteFile: jest.fn(),
    } as unknown as FilesContextData)

    // Start a prompt to create a new refinement
    await act(async () => {
      await result.current.submitPrompt('new prompt', 'generate')
    })

    // We should now have two refinements
    expect(setPreviousRefinements).toHaveBeenCalledTimes(2)

    // Cancel the prompt
    await act(async () => {
      result.current.cancelPrompt()
    })

    // Should go back to just the original refinement
    expect(setPreviousRefinements).toHaveBeenCalledTimes(3)
  })

  it('correctly sets isFetching to false when COMPLETE event is received with stop reason', async () => {
    const {result} = renderUseWorkbench()

    let onEvent: ((event: FileStreamEvent) => void) | undefined

      // Mock generateIteration to capture the onEvent callback
    ;(generateIteration as jest.Mock).mockImplementationOnce(
      ({onEvent: callback}: {onEvent: (event: FileStreamEvent) => void}) => {
        onEvent = callback
        return Promise.resolve([])
      },
    )

    // Start the prompt submission
    await act(async () => {
      await result.current.submitPrompt('test prompt', 'generate')
    })

    // Simulate a COMPLETE event with 'stop' reason
    await act(async () => {
      if (onEvent) {
        onEvent({
          type: FileStreamEventType.COMPLETE,
          finishReason: 'stop',
          files: [
            {
              fileName: 'test.js',
              content: 'console.log("Hello world");',
            },
          ],
        })
      }
    })

    // Verify isFetching is set to false
    expect(setIsFetching).toHaveBeenCalledWith(false)
  })

  it('calls cancel endpoint during a cancellation', async () => {
    // Mock fetch from codespace API with a successful response
    const mockFetchFromCodespaceApi = jest.fn().mockResolvedValue({
      ok: true,
    })
    jest.mocked(useFetchFromCodespaceApi).mockReturnValue({
      fetchFromCodespaceApi: mockFetchFromCodespaceApi,
    })

    const {result} = renderUseWorkbench()

    // Call cancelPrompt
    await act(async () => {
      await result.current.cancelPrompt()
    })

    // Verify that fetchFromCodespaceApi was called with the correct endpoint and method
    expect(mockFetchFromCodespaceApi).toHaveBeenCalledWith('/cancel', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
    })

    // Verify that the state was updated
    expect(setIsFetching).toHaveBeenCalledWith(false)
    expect(setIsLoadingFromModel).toHaveBeenCalledWith(false)
    expect(setIsOptimisticLoading).toHaveBeenCalledWith(false)
  })

  it('handles API errors when canceling', async () => {
    // Mock an error from the API
    const mockFetchFromCodespaceApi = jest.fn().mockRejectedValue(new Error('API error'))
    jest.mocked(useFetchFromCodespaceApi).mockReturnValue({
      fetchFromCodespaceApi: mockFetchFromCodespaceApi,
    })

    // Mock onError function for error tracking
    const mockOnError = jest.fn()

    const {result} = renderUseWorkbench({workbenchStore: {onError: mockOnError}})

    await act(async () => {
      await result.current.cancelPrompt()
    })

    // Verify that error was handled and reported
    expect(mockOnError).toHaveBeenCalledWith({
      service: Service.RUNTIME,
    })

    // Verify that the state was still updated despite the error
    expect(setIsFetching).toHaveBeenCalledWith(false)
    expect(setIsLoadingFromModel).toHaveBeenCalledWith(false)
  })

  it('cleans up refinements when canceling', async () => {
    // Mock successful API response
    const mockFetchFromCodespaceApi = jest.fn().mockResolvedValue({ok: true})
    jest.mocked(useFetchFromCodespaceApi).mockReturnValue({
      fetchFromCodespaceApi: mockFetchFromCodespaceApi,
    })

    // Setup mock refinements with previous refinements
    const mockPreviousRefinements = [
      {id: 1, prompt: 'First prompt', files: {}, iteration_type: 'ai' as const},
      {id: 2, prompt: 'Second prompt', files: {}, iteration_type: 'ai' as const},
    ]
    jest.mocked(useIterationHistory).mockReturnValue({
      previousRefinements: mockPreviousRefinements,
      setPreviousRefinements,
      setCurrentRefinement,
      currentRefinementId: 2,
      isNavigatingHistory: false,
      setIsNavigatingHistory: jest.fn(),
    })

    const {result} = renderUseWorkbench()

    // Call cancelPrompt
    await act(async () => {
      await result.current.cancelPrompt()
    })

    // Verify that refinements were properly cleaned up
    expect(setCurrentRefinement).toHaveBeenCalledWith(1)
    expect(setPreviousRefinements).toHaveBeenCalledWith([mockPreviousRefinements[0]])

    // Verify that the prompt text was reset
    expect(setPromptText).toHaveBeenCalledWith('Second prompt')
  })

  it('sets iterationStartTime when submitting a prompt', async () => {
    const mockSetIterationStartTime = jest.fn()
    jest.mocked(useWorkbenchContext).mockReturnValue({
      id: 'test-id',
      updatedAt: '2025-10-01T00:00:00Z',
      setUpdatedAt: jest.fn(),
      setIsFetching,
      setIsOptimisticLoading,
      setIsLoadingFromModel,
      initialPromptSubmitted: {current: false},
      iterationStartTime: null,
      setIterationStartTime: mockSetIterationStartTime,
      name: '',
      setName: jest.fn(),
      description: '',
      setDescription: jest.fn(),
      deployUrl: '',
      setDeployUrl: jest.fn(),
      repositoryUrl: undefined,
      setRepositoryUrl: jest.fn(),
      runtimePermanentName: '',
      friendlyName: '',
      isFetching: false,
      isOptimisticLoading: false,
      isMobileSidebarOpen: false,
      setIsMobileSidebarOpen: jest.fn(),
      isLoadingFromModel: false,
      setFriendlyName: jest.fn(),
      userAgentModelPreference: 'claude-3.7-sonnet',
      setUserAgentModelPreference: jest.fn(),
      sparkAgentModel: 'claude-3.7-sonnet',
      sparkFileUrl: jest.fn(),
      sparkBaseUrl: jest.fn(),
    })

    const {result} = renderUseWorkbench()

    // Call submitPrompt
    await act(async () => {
      await result.current.submitPrompt('test prompt', 'generate')
    })

    // Verify that setIterationStartTime was called with a timestamp (any number)
    expect(mockSetIterationStartTime).toHaveBeenCalled()
    expect(typeof mockSetIterationStartTime.mock.calls[0][0]).toBe('number')
  })

  it('resets iterationStartTime when canceling a prompt', async () => {
    // Mock fetch from codespace API with a successful response
    const mockFetchFromCodespaceApi = jest.fn().mockResolvedValue({
      ok: true,
    })
    jest.mocked(useFetchFromCodespaceApi).mockReturnValue({
      fetchFromCodespaceApi: mockFetchFromCodespaceApi,
    })

    const mockSetIterationStartTime = jest.fn()
    jest.mocked(useWorkbenchContext).mockReturnValue({
      id: 'test-id',
      updatedAt: '2023-10-01T00:00:00Z',
      setUpdatedAt: jest.fn(),
      setIsFetching,
      setIsOptimisticLoading,
      setIsLoadingFromModel,
      initialPromptSubmitted: {current: false},
      iterationStartTime: 1234567890,
      setIterationStartTime: mockSetIterationStartTime,
      name: '',
      setName: jest.fn(),
      description: '',
      setDescription: jest.fn(),
      deployUrl: '',
      setDeployUrl: jest.fn(),
      repositoryUrl: undefined,
      setRepositoryUrl: jest.fn(),
      runtimePermanentName: '',
      friendlyName: '',
      isFetching: false,
      isOptimisticLoading: false,
      isMobileSidebarOpen: false,
      setIsMobileSidebarOpen: jest.fn(),
      isLoadingFromModel: false,
      setFriendlyName: jest.fn(),
      userAgentModelPreference: 'claude-3.7-sonnet',
      setUserAgentModelPreference: jest.fn(),
      sparkAgentModel: 'claude-3.7-sonnet',
      sparkFileUrl: jest.fn(),
      sparkBaseUrl: jest.fn(),
    })

    const {result} = renderUseWorkbench()

    // Call cancelPrompt
    await act(async () => {
      await result.current.cancelPrompt()
    })

    // Verify that setIterationStartTime was called with null
    expect(mockSetIterationStartTime).toHaveBeenCalledWith(null)
  })
})

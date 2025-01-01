import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {
  useWorkspaceEditorUIDispatch,
  useWorkspaceEditorUIState,
} from '@github-ui/workspace-editor/contexts/WorkspaceEditorUIContext'
import type {WorkspaceEditorUIState} from '@github-ui/workspace-editor/utilities/workspace-editor-ui-reducer'
import {act, renderHook, waitFor} from '@testing-library/react'
import type {ReactNode} from 'react'

import {MockAgentApi} from '../../__tests__/utilities/mock-agent-api'
import {MockAgentEventStream, ServerEventFactory} from '../../__tests__/utilities/mock-agent-event-stream'
import {useAnalytics} from '../../telemetry/use-analytics'
import type {WorkbenchRoutePayload} from '../../types/workbench-types'
import {type CodespaceContext, useCodespaceContext} from '../CodespaceContext'
import {type FileSyncerContextData, useFileSyncerContext} from '../FileSyncerContext'
import {IterationHistoryProvider, useIterationHistory} from '../IterationHistoryContext'
import {ConnectionStatus, ServerEventsProvider, useServerEvents} from '../ServerEventsContext'
import {UserPromptContextProvider, useUserPromptContext} from '../UserPromptContext'
import {useWorkbenchContext, type WorkbenchContextData} from '../WorkbenchContext'
import type {WorkbenchStoreContext} from '../WorkbenchStoreContext'
import {AgentStatus, Service, useWorkbenchStore} from '../WorkbenchStoreContext'

// Mock all the dependencies
jest.mock('@github-ui/react-core/use-route-payload', () => ({
  useRoutePayload: jest.fn(),
}))

jest.mock('../../telemetry/use-analytics', () => ({
  useAnalytics: jest.fn(),
}))

jest.mock('@github-ui/workspace-editor/contexts/WorkspaceEditorUIContext', () => ({
  useWorkspaceEditorUIDispatch: jest.fn(),
  useWorkspaceEditorUIState: jest.fn(),
}))

jest.mock('../../hooks/use-fetch-from-codespace-api')

jest.mock('../CodespaceContext', () => ({
  useCodespaceContext: jest.fn(),
}))

jest.mock('../FileSyncerContext', () => ({
  useFileSyncerContext: jest.fn(),
}))

jest.mock('../WorkbenchContext', () => ({
  useWorkbenchContext: jest.fn(),
}))

jest.mock('../WorkbenchStoreContext', () => ({
  AgentStatus: {
    IDLE: 'idle',
    GENERATING: 'generating',
  },
  Service: {
    AGENT: 'agent',
    VITE: 'vite',
    CODESPACE: 'codespace',
  },
  useWorkbenchStore: jest.fn(),
}))

describe('ServerEventsContext', () => {
  // Set up mock implementations for hooks
  const mockSetIsFetching = jest.fn()
  const mockSetIterationStartTime = jest.fn()
  const mockDispatch = jest.fn()
  const mockOnConnected = jest.fn()
  const mockOnSuccess = jest.fn()
  const mockOnStatus = jest.fn()
  const mockOnError = jest.fn()
  const mockSendEvent = jest.fn()
  const spyFetch = jest.spyOn(global, 'fetch')

  // Hook to be rendered for full test state
  const useProvidersUnderTest = () => {
    const serverEventsContext = useServerEvents()
    const iterationHistoryContext = useIterationHistory()
    const UserPromptContext = useUserPromptContext()
    return {
      ...serverEventsContext,
      ...iterationHistoryContext,
      ...UserPromptContext,
    }
  }

  // Set up our wrapper component to provide the context
  const wrapper = ({children}: {children: ReactNode}) => {
    return (
      <UserPromptContextProvider>
        <IterationHistoryProvider>
          <ServerEventsProvider>{children}</ServerEventsProvider>
        </IterationHistoryProvider>
      </UserPromptContextProvider>
    )
  }

  beforeEach(() => {
    jest.clearAllMocks()

    // Mock useRoutePayload
    jest.mocked(useRoutePayload).mockReturnValue({
      workbench: {
        id: 'test-workbench-id',
      },
    } as WorkbenchRoutePayload)

    // Mock useAnalytics
    jest.mocked(useAnalytics).mockReturnValue(mockSendEvent)

    // Mock useWorkspaceEditorUIDispatch and useWorkspaceEditorUIState
    jest.mocked(useWorkspaceEditorUIDispatch).mockReturnValue(mockDispatch)
    jest.mocked(useWorkspaceEditorUIState).mockReturnValue({
      banner: undefined,
    } as WorkspaceEditorUIState)

    // Mock useCodespaceContext
    jest.mocked(useCodespaceContext).mockReturnValue({
      codespaceData: {
        codespaceState: 'ready',
      },
    } as CodespaceContext)

    // Mock useFileSyncerContext
    jest.mocked(useFileSyncerContext).mockReturnValue({
      getFileSyncerV2: jest.fn(),
    } as unknown as FileSyncerContextData)

    // Mock useWorkbenchContext
    jest.mocked(useWorkbenchContext).mockReturnValue({
      setIsFetching: mockSetIsFetching,
      iterationStartTime: Date.now(),
      setIterationStartTime: mockSetIterationStartTime,
    } as unknown as WorkbenchContextData)

    // Mock useWorkbenchStore
    jest.mocked(useWorkbenchStore).mockReturnValue({
      status: {},
      onConnected: mockOnConnected,
      onSuccess: mockOnSuccess,
      onStatus: mockOnStatus,
      onError: mockOnError,
    } as unknown as WorkbenchStoreContext)
  })

  afterEach(() => {
    // Cleanup the mock event stream
    MockAgentEventStream.getInstance().reset()
  })

  beforeAll(() => {
    // Initialize the mock server
    MockAgentApi.getInstance().getServer().listen()
  })

  afterAll(() => {
    // Cleanup the mock server
    MockAgentApi.getInstance().getServer().close()
    spyFetch.mockRestore()
  })

  it('should establish a connection and process events on mount', async () => {
    // Create a mock event stream with a sequence of events
    MockAgentEventStream.getInstance()
      .addEvent(ServerEventFactory.connected())
      .addEvent(ServerEventFactory.heartbeat())
      .addEvent(ServerEventFactory.serverReady())

    // Render the hook
    const {result} = renderHook(useProvidersUnderTest, {wrapper})

    // Wait for connection to be established and events to be processed
    await waitFor(() => expect(result.current.connectionStatus).toBe(ConnectionStatus.CONNECTED))
    await waitFor(() => expect(result.current.events.length).toBe(3))

    // Verify API call
    expect(spyFetch).toHaveBeenCalledWith(`${MockAgentApi.BASE_URL}/events`, expect.any(Object))

    // Verify expected events were captured
    expect(result.current.events[0]?.type).toBe('connected')
    expect(result.current.events[1]?.type).toBe('heartbeat')
    expect(result.current.events[2]?.type).toBe('server:ready')

    // Verify appropriate status callbacks were made
    expect(mockOnConnected).toHaveBeenCalledWith({service: Service.AGENT})
  })

  it('should process build events correctly', async () => {
    // Create a mock event stream with build events
    MockAgentEventStream.getInstance()
      .addEvent(ServerEventFactory.connected())
      .addEvent(ServerEventFactory.serverReady())
      .addEvent(ServerEventFactory.buildStarted('test.js'))
      .addEvent(ServerEventFactory.buildSuccess('test.js'))

    // Render the hook
    const {result} = renderHook(useProvidersUnderTest, {wrapper})

    // Wait for events to be processed
    await waitFor(() => expect(result.current.events.length).toBe(4))

    // Verify build events were captured
    expect(result.current.events[2]?.type).toBe('build:started')
    expect(result.current.events[3]?.type).toBe('build:success')
  })

  it('should process agent events and update iteration history', async () => {
    const requestId = 'request-123'
    const iterationId = 42
    const commitSha = 'abc123'
    const prompt = 'Test prompt'
    const parentId = 41
    const filePath = 'src/test.js'
    const mockStartTime = Date.now()

    // Mock iterationStartTime for analytics tracking
    jest.mocked(useWorkbenchContext).mockReturnValue({
      setIsFetching: mockSetIsFetching,
      iterationStartTime: mockStartTime,
      setIterationStartTime: mockSetIterationStartTime,
    } as unknown as WorkbenchContextData)

    // Create a mock event stream with agent events
    MockAgentEventStream.getInstance()
      .addEvent(ServerEventFactory.connected())
      .addEvent(ServerEventFactory.serverReady())
      .addEvent(ServerEventFactory.agentStarted(requestId, iterationId, prompt, parentId))
      .addEvent(ServerEventFactory.agentUpdate(requestId, iterationId, 'Processing changes...', parentId))
      .addEvent(ServerEventFactory.fileUpdateStarted(requestId, iterationId, filePath))
      .addEvent(ServerEventFactory.fileUpdateSucceeded(requestId, iterationId, filePath))
      .addEvent(
        ServerEventFactory.agentSucceeded(
          requestId,
          iterationId,
          commitSha,
          [{path: filePath, action: 'modified'}],
          parentId,
        ),
      )
      .addEvent(
        ServerEventFactory.iterationCommitted(
          iterationId,
          commitSha,
          {
            [filePath]: {editType: 'update', fileName: filePath},
          },
          'ai',
          parentId,
          prompt,
        ),
      )

    // Mock the fetch response with our event stream

    // Render the hook
    const {result} = renderHook(useProvidersUnderTest, {wrapper})

    // Wait for events to be processed
    await waitFor(() => expect(result.current.events.length).toBe(8))

    // Verify agent events were captured and processed
    expect(result.current.events[2]?.type).toBe('agent:started')
    expect(result.current.events[3]?.type).toBe('agent:update')
    expect(result.current.events[6]?.type).toBe('agent:succeeded')

    // Verify iteration events were processed
    expect(result.current.events[7]?.type).toBe('iteration:committed')

    // Verify status updates were called
    expect(mockOnStatus).toHaveBeenCalledWith({service: Service.AGENT, status: AgentStatus.GENERATING})
    expect(mockOnSuccess).toHaveBeenCalledWith({service: Service.AGENT})

    // Verify iteration history was updated
    expect(result.current.currentRefinementId).toBe(iterationId)

    // Verify analytics event was sent
    expect(mockSendEvent).toHaveBeenCalledWith('iterate_completed', {
      time_to_iterate_ms: expect.any(Number),
      iteration_id: iterationId,
    })

    // Verify iteration timer was reset
    expect(mockSetIterationStartTime).toHaveBeenCalledWith(null)
  })

  it('should handle agent failure events', async () => {
    const requestId = 'request-123'
    const iterationId = 42
    const errorMessage = 'Something went wrong'
    const parentId = 41

    jest.mocked(useRoutePayload).mockReturnValue({
      workbench: {
        id: 'test-workbench-id',
        currentRefinementId: parentId,
        previousRefinements: [
          {
            id: parentId,
          },
          {
            id: iterationId,
            prompt: 'Test prompt',
          },
        ],
      },
    } as WorkbenchRoutePayload)

    // Create a mock event stream with agent failure event
    MockAgentEventStream.getInstance()
      .addEvent(ServerEventFactory.connected())
      .addEvent(ServerEventFactory.serverReady())
      .addEvent(ServerEventFactory.agentStarted(requestId, iterationId, 'Test prompt', parentId))
      .addEvent(ServerEventFactory.agentFailed(requestId, iterationId, errorMessage, parentId))

    // Render the hook
    const {result} = renderHook(useProvidersUnderTest, {wrapper})

    // Wait for events to be processed
    await waitFor(() => expect(result.current.events.length).toBe(4))

    // Verify agent failure was processed
    expect(result.current.events[3]?.type).toBe('agent:failed')

    // Verify error was handled
    expect(mockOnError).toHaveBeenCalledWith({service: Service.AGENT})

    // Verify error is in the context
    expect(result.current.errors).toEqual([{message: errorMessage}])

    // Verify that the state was rolled back with the error
    await waitFor(() => expect(result.current.currentRefinementId).toBe(parentId))
    expect(result.current.previousRefinements).toEqual([
      {
        id: parentId,
      },
    ])
    expect(result.current.promptText).toBe('Test prompt')
    expect(result.current.promptError).toBe(errorMessage)
  })

  it('should automatically reconnect after a failure to connect', async () => {
    // Setup: Use fake timers to control the retry delays
    jest.useFakeTimers()

    // First create a mock that fails with an error
    spyFetch.mockRejectedValueOnce(new Error('Connection failed'))

    // Then on retry, succeed with events
    MockAgentEventStream.getInstance()
      .addEvent(ServerEventFactory.connected())
      .addEvent(ServerEventFactory.serverReady())

    // Render the hook
    const {result} = renderHook(useProvidersUnderTest, {wrapper})

    // Act: Wait for initial connection attempt to fail
    await waitFor(() => expect(spyFetch).toHaveBeenCalledTimes(1))

    // Assert: Since the connection failed, we'll see the connection status as connecting still
    expect(result.current.connectionStatus).toBe(ConnectionStatus.CONNECTING)

    // Advance timers to trigger the retry (first retry delay is 1000ms)
    act(() => jest.advanceTimersByTime(1000))

    // Wait for the retry to be processed
    await waitFor(() => expect(spyFetch).toHaveBeenCalledTimes(2))

    // Wait for retry to complete and check server is ready
    await waitFor(() => expect(result.current.connectionStatus).toBe(ConnectionStatus.CONNECTED))

    // Cleanup
    jest.useRealTimers()
  })

  it('should automatically reconnect after an unexpected disconnection', async () => {
    // Setup: Use fake timers to control heartbeat checks
    jest.useFakeTimers()

    // Initial successful connection
    MockAgentEventStream.getInstance()
      .addEvent(ServerEventFactory.connected())
      .addEvent(ServerEventFactory.serverReady())
      .addEvent(ServerEventFactory.heartbeat())

    // Render the hook
    const {result} = renderHook(useProvidersUnderTest, {wrapper})

    // Wait for initial connection to succeed
    await waitFor(() => expect(result.current.connectionStatus).toBe(ConnectionStatus.CONNECTED))

    // Initial connection should have 3 events (connected, ready, heartbeat)
    expect(result.current.events.length).toBe(3)
    expect(spyFetch).toHaveBeenCalledTimes(1)

    // Advance timers by more than the 30 seconds heartbeat timeout
    // This should trigger a reconnection because no events were received in that time
    act(() => jest.advanceTimersByTime(1000 * 35))

    // Second connection after heartbeat timeout
    MockAgentEventStream.getInstance()
      .reset()
      .addEvent(ServerEventFactory.connected())
      .addEvent(ServerEventFactory.serverReady())
      .addEvent(ServerEventFactory.heartbeat()) // New heartbeat on reconnection

    // Wait for the automatic reconnection to be triggered
    await waitFor(() => expect(spyFetch).toHaveBeenCalledTimes(2))

    // Wait for the new connection to process events
    await waitFor(() => expect(result.current.events.length).toBe(6))

    // We should have 6 events total (3 from first connection + 3 from reconnect)
    expect(result.current.events[0]?.type).toBe('connected')
    expect(result.current.events[1]?.type).toBe('server:ready')
    expect(result.current.events[2]?.type).toBe('heartbeat')
    expect(result.current.events[3]?.type).toBe('connected')
    expect(result.current.events[4]?.type).toBe('server:ready')
    expect(result.current.events[5]?.type).toBe('heartbeat')

    // Verify the connection status is still connected
    expect(result.current.connectionStatus).toBe(ConnectionStatus.CONNECTED)

    // Cleanup
    jest.useRealTimers()
  })

  it('should handle manual reconnection', async () => {
    // First succeed with initial connection
    MockAgentEventStream.getInstance()
      .addEvent(ServerEventFactory.connected())
      .addEvent(ServerEventFactory.serverReady())

    // Render the hook
    const {result} = renderHook(useProvidersUnderTest, {wrapper})

    // Wait for initial connection to succeed
    await waitFor(() => expect(result.current.connectionStatus).toBe(ConnectionStatus.CONNECTED))
    expect(result.current.events.length).toBe(2)
    expect(spyFetch).toHaveBeenCalledTimes(1)

    // Trigger manual reconnection
    act(() => {
      result.current.reconnect()
    })

    // Then provide events for reconnection
    MockAgentEventStream.getInstance()
      .reset()
      .addEvent(ServerEventFactory.connected())
      .addEvent(ServerEventFactory.serverReady())
      .addEvent(ServerEventFactory.heartbeat()) // Additional event to verify new connection

    // Wait for reconnection to be processed
    await waitFor(() => expect(spyFetch).toHaveBeenCalledTimes(2))

    // Wait for reconnection to succeed with new events (should have all combined events)
    await waitFor(() => expect(result.current.events.length).toBe(5))

    // Verify fetch was called twice (initial + reconnect)
    expect(spyFetch).toHaveBeenCalledTimes(2)
  })
})

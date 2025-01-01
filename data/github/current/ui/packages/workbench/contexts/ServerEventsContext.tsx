import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useDebounce} from '@github-ui/use-debounce'
import {
  useWorkspaceEditorUIDispatch,
  useWorkspaceEditorUIState,
} from '@github-ui/workspace-editor/contexts/WorkspaceEditorUIContext'
import {BannerType} from '@github-ui/workspace-editor/utilities/workspace-editor-types'
import type React from 'react'
import type {ReactNode} from 'react'
import {createContext, useCallback, useContext, useEffect, useMemo, useRef, useState} from 'react'

import {useFetchFromCodespaceApi} from '../hooks/use-fetch-from-codespace-api'
import {useAnalytics} from '../telemetry/use-analytics'
import type {BuildFailedEvent, BuildSuccessEvent, ServerEvent} from '../types/server-event-types'
import type {Iteration} from '../types/workbench-types'
import {ServerEventStreamer} from '../utilities/server-event-streamer'
import {useCodespaceContext} from './CodespaceContext'
import {useIterationHistory} from './IterationHistoryContext'
import {useUserPromptContext} from './UserPromptContext'
import {useWorkbenchContext} from './WorkbenchContext'
import {AgentStatus, Service, useWorkbenchStore} from './WorkbenchStoreContext'

export const isBuildFailedEvent = (event: ServerEvent): event is BuildFailedEvent => {
  return event.type === 'build:failed'
}

export const isBuildSuccessEvent = (event: ServerEvent): event is BuildSuccessEvent => {
  return event.type === 'build:success'
}

export const ConnectionStatus = {
  // We have completely failed to connect to the server. We have exhausted all retries.
  DISCONNECTED: 'DISCONNECTED',
  // We are currently connected to the server.
  CONNECTED: 'CONNECTED',
  // We are attempting to establish a connection from a failed state. This is either because it's our first attempt to connect, or because we were previously in a DISCONNECTED (ie, failed) state.
  CONNECTING: 'CONNECTING',
  // We are attempting to reconnect to the server to keep the connection alive and preserve a CONNECTED (ie, successful) state. This is either because of transient network issues, or because DevTunnels max request times of 60 seconds has been exceeded.
  RECONNECTING: 'RECONNECTING',
} as const

export type ConnectionStatus = (typeof ConnectionStatus)[keyof typeof ConnectionStatus]

interface InteractionError {
  message: string
  statusCode?: number
}

export interface ServerEventsContextType {
  isServerConnected: boolean
  connectionStatus: ConnectionStatus
  events: ServerEvent[]
  fetchFromCodespaceApi: (path: string, init?: RequestInit) => Promise<Response>
  errors: InteractionError[]
  reconnect: () => void
  latestAgentUpdate?: string
}

export const ServerEventsContext = createContext<ServerEventsContextType | undefined>(undefined)

interface ServerEventsProviderProps {
  children: ReactNode
}

const MAX_RETRIES = 5
const RETRY_DELAYS = [1000, 3000, 7000, 15000, 25000]

// check if the message ends in a non-alphanumeric character and remove it (except periods)
// then if the formatted message does not end in a period, add one
const parseAgentUpdate = (message: string): string => {
  const formattedMessage = message.replace(/[^a-zA-Z0-9.]+$/, '').trim()
  return formattedMessage.endsWith('.') ? formattedMessage : `${formattedMessage}.`
}

export const ServerEventsProvider: React.FC<ServerEventsProviderProps> = ({children}) => {
  const {
    codespaceData: {codespaceState},
  } = useCodespaceContext()
  const {setIsFetching, iterationStartTime, setIterationStartTime} = useWorkbenchContext()
  const {setPreviousRefinements, setCurrentRefinement} = useIterationHistory()
  const {fetchFromCodespaceApi} = useFetchFromCodespaceApi()
  const dispatch = useWorkspaceEditorUIDispatch()
  const {banner} = useWorkspaceEditorUIState()
  const {
    status: {[Service.AGENT]: agentStatus},
    onConnected,
    onSuccess,
    onStatus,
    onError,
  } = useWorkbenchStore()
  const {setPromptText, setPromptError} = useUserPromptContext()
  const responseReader = useRef<ServerEventStreamer | undefined>(undefined)
  const abortController = useRef<AbortController | undefined>(undefined)
  const sendEvent = useAnalytics()
  const reconnectOnFocusEnabled = useFeatureFlag('copilot_workbench_reconnect_on_focus')

  const [events, setEvents] = useState<ServerEvent[]>([])

  const [errors, setErrors] = useState<InteractionError[]>([])
  const [connectionStatus, setConnectionStatus] = useState<ConnectionStatus>(ConnectionStatus.DISCONNECTED)
  const [latestAgentUpdate, setLatestAgentUpdate] = useState('')

  // Refs to keep track of the health of our connection
  // - lastEventTimeRef - Keep track of the timestamp of the last event we received
  // - heartbeatCheckRef - Keep track of our "heartbeat" connection interval to avoid zombie connections
  const heartbeatCheckRef = useRef<NodeJS.Timeout | undefined>(undefined)
  const lastEventTimeRef = useRef<Date>(new Date())

  // Refs to keep track of retry logic
  // - retryCountRef - Keep track of the number of retries we've attempted
  // - retryTimeoutRef - Keep track of the retry interval to avoid retrying too quickly
  const retryCountRef = useRef(0)
  const retryTimeoutRef = useRef<NodeJS.Timeout | undefined>(undefined)

  // Get around circular dependency because these memoized functions call each other
  const establishConnectionRef = useRef<((manualReconnect?: boolean) => Promise<void>) | undefined>(undefined)
  const handleConnectionErrorRef = useRef<((err?: unknown) => void) | undefined>(undefined)

  const updateIteration = useCallback(
    (iterationId: number, updateFn: (iteration: Iteration) => Iteration) => {
      setPreviousRefinements(prevIterations => {
        const index = prevIterations.findIndex(iter => iter.id === iterationId)

        if (index >= 0) {
          const updatedIterations = [...prevIterations]
          updatedIterations[index] = updateFn(updatedIterations[index]!)
          return updatedIterations
        } else {
          return prevIterations
        }
      })
    },
    [setPreviousRefinements],
  )

  const processStreamingMessage = useCallback(
    async (chunk: ServerEvent) => {
      if (!chunk || !chunk.type || !chunk.timestamp) return

      lastEventTimeRef.current = new Date(chunk.timestamp)
      setEvents(prev => [...prev, chunk])

      // Handle specific event types that need additional processing
      switch (chunk.type) {
        case 'connected':
          if (chunk.details.currentIterationId) {
            setIsFetching(true)
          }
          break
        case 'server:ready':
          if (agentStatus !== AgentStatus.GENERATING) {
            onConnected({service: Service.AGENT})
          }
          sendEvent('server_ready', {
            connection_retry_count: retryCountRef.current,
          })
          break
        case 'agent:started':
          setIsFetching(true)
          onStatus({service: Service.AGENT, status: AgentStatus.GENERATING})
          sendEvent('agent_started', {
            iteration_id: chunk.details.iterationId,
          })
          break
        case 'agent:update':
          setLatestAgentUpdate(parseAgentUpdate(chunk.details.message))
          sendEvent('agent_update', {
            message_length: chunk.details.message.length,
          })
          break
        case 'agent:failed': {
          const {statusCode, message} = chunk.details.error
          setErrors(prev => [...prev, {statusCode, message}])
          setIsFetching(false)
          onError({service: Service.AGENT})

          const iterationId = chunk.details.iterationId
          const parentId = chunk.details.parentId

          setPreviousRefinements(prevIterations => {
            const index = prevIterations.findIndex(iter => iter.id === iterationId)
            if (index < 0) return prevIterations

            const updatedIterations = prevIterations.filter(iter => iter.id !== iterationId)
            const failedIteration = prevIterations[index]!

            setPromptText(failedIteration.prompt || '')
            setCurrentRefinement(parentId || undefined)
            setPromptError(chunk.details.error.message)

            return updatedIterations
          })

          sendEvent('agent_failed', {
            iteration_id: iterationId,
            parent_id: parentId ?? null,
            error_message: chunk.details.error.message,
            error_code: chunk.details.error.statusCode ?? null,
          })

          break
        }
        case 'agent:succeeded': {
          setErrors([])
          setIsFetching(false)
          setLatestAgentUpdate('')
          onSuccess({service: Service.AGENT})

          const iterationId = chunk.details.iterationId
          updateIteration(iterationId, iteration => ({
            ...iteration,
            sha: chunk.details.commitSha,
            parentId: chunk.details.parentId,
          }))

          setCurrentRefinement(chunk.details.iterationId)
          // Store a metric for the iteration completion
          if (iterationStartTime !== null) {
            sendEvent('iterate_completed', {
              time_to_iterate_ms: Date.now() - iterationStartTime,
              iteration_id: chunk.details.iterationId,
            })
          }
          setIterationStartTime(null)

          break
        }

        case 'suggestion:completed': {
          const suggestions = chunk.details.suggestions
          const iterationId = chunk.details.iterationId
          if (suggestions && Array.isArray(suggestions) && suggestions.length === 3) {
            updateIteration(iterationId, iteration => ({
              ...iteration,
              suggestions,
            }))
          }

          sendEvent('suggestion_completed', {
            iteration_id: iterationId,
            suggestions_count: suggestions?.length || 0,
          })

          break
        }
        case 'file:create:started':
        case 'file:update:started': {
          // WHY IS THIS COMMENTED OUT?
          // ---
          // 1. Claude model buffers tool arguments before streaming them out.
          // 2. This means, on the VM Agent/Server side, we get the entire tool call from the model in one chunk.
          // 3. This means that the tool to create/update files, which includes the new content in the tool call,
          //    arrives in the same chunk that would indicate to us that we are going to modify or create the file.
          // 4. Therefore, we will always send a STARTED event just MS before sending the SUCCEEDED message.
          // 5. Therefore, there is no reason to handle this at the moment.
          //
          // setPreviousRefinements((prevRefinements: Iteration[]) => {
          //   const lastRefinement = prevRefinements[prevRefinements.length - 1]
          //   if (!lastRefinement) return prevRefinements

          //   // Check if this file path is already in the record
          //   const fileExists = lastRefinement.files && lastRefinement.files[chunk.details.path]

          //   // If the file already exists in the record, no need to update
          //   if (fileExists) return prevRefinements

          //   // Create updated files record with the new file
          //   const updatedFiles = {
          //     ...lastRefinement.files,
          //     [chunk.details.path]: {fileName: chunk.details.path},
          //   }

          //   // Update the refinement with the new files record
          //   const updatedRefinement: Iteration = {...lastRefinement, files: updatedFiles}

          //   return [...prevRefinements.slice(0, -1), updatedRefinement]
          // })

          sendEvent('file_operation_started', {
            operation: chunk.type === 'file:create:started' ? 'create' : 'update',
            path: chunk.details.path,
            iteration_id: chunk.details.iterationId,
          })

          break
        }
        case 'file:create:succeeded':
        case 'file:update:succeeded': {
          const iterationId = chunk.details.iterationId
          updateIteration(iterationId, iteration => {
            const updatedFiles = {
              ...iteration.files,
              [chunk.details.path]: {
                fileName: chunk.details.path,
                editType: chunk.type === 'file:create:succeeded' ? ('create' as const) : ('update' as const),
              },
            }

            return {
              ...iteration,
              files: updatedFiles,
            }
          })

          sendEvent('file_operation_succeeded', {
            operation: chunk.type === 'file:create:succeeded' ? 'create' : 'update',
            path: chunk.details.path,
            iteration_id: iterationId,
          })

          break
        }
        case 'iteration:committed': {
          const iterationId = chunk.details.iterationId
          updateIteration(iterationId, iteration => ({
            ...iteration,
            sha: chunk.details.commitSha,
            parentId: chunk.details.parentId,
            files: chunk.details.files,
          }))

          if (chunk.details.iteration_type === 'ai') {
            setCurrentRefinement(iterationId)
          }

          sendEvent('iteration_committed', {
            iteration_id: iterationId,
            iteration_type: chunk.details.iteration_type,
            commit_sha: chunk.details.commitSha,
            file_count: Object.keys(chunk.details.files || {}).length,
          })

          break
        }
        case 'iteration:created': {
          const iteration: Iteration = {
            id: chunk.details.iterationId,
            sha: chunk.details.commitSha,
            iteration_type: chunk.details.iteration_type,
            prompt: chunk.details.prompt,
            parentId: chunk.details.parentId,
            files: {},
          }
          setPreviousRefinements(prevRefinements => {
            const lastRefinement = prevRefinements[prevRefinements.length - 1]

            // If the last refinement is an AI type without an ID, replace it with created iteration.
            if (lastRefinement && lastRefinement.iteration_type === 'ai' && !lastRefinement.id) {
              return [...prevRefinements.slice(0, -1), iteration]
            }

            return prevRefinements
          })
          setCurrentRefinement(chunk.details.iterationId)

          sendEvent('iteration_created', {
            iteration_id: chunk.details.iterationId,
            iteration_type: chunk.details.iteration_type,
            has_parent: !!chunk.details.parentId,
            prompt_length: chunk.details.prompt?.length || 0,
          })

          break
        }
      }
    },
    [
      agentStatus,
      onConnected,
      setIsFetching,
      onStatus,
      onError,
      setCurrentRefinement,
      onSuccess,
      iterationStartTime,
      setIterationStartTime,
      setPreviousRefinements,
      updateIteration,
      setPromptText,
      setPromptError,
      sendEvent,
    ],
  )

  const closeConnection = useCallback(() => {
    if (responseReader.current) {
      responseReader.current.stop()
      responseReader.current = undefined
    }

    if (abortController.current) {
      abortController.current.abort()
      abortController.current = undefined
    }
  }, [])

  const showConnectionErrorBanner = useCallback(() => {
    dispatch({type: 'SET_BANNER', banner: BannerType.CONNECTION_ERROR})
  }, [dispatch])

  const hideConnectionErrorBanner = useCallback(() => {
    if (banner !== BannerType.CONNECTION_ERROR) return
    dispatch({type: 'SET_BANNER', banner: undefined})
  }, [banner, dispatch])

  const handleConnectionError = useCallback(() => {
    if (retryCountRef.current < MAX_RETRIES) {
      const retryDelay = RETRY_DELAYS[retryCountRef.current]

      retryTimeoutRef.current = setTimeout(() => {
        establishConnectionRef.current?.()
        retryCountRef.current++
      }, retryDelay)
    } else {
      setConnectionStatus(ConnectionStatus.DISCONNECTED)
      showConnectionErrorBanner()
    }
  }, [showConnectionErrorBanner])
  handleConnectionErrorRef.current = handleConnectionError

  const handleStreamingMessage = useCallback(
    async (streamer: ServerEventStreamer) => {
      try {
        for await (const chunk of streamer.stream()) {
          await processStreamingMessage(chunk)
        }
      } catch (err) {
        handleConnectionErrorRef.current?.(err)
      }
    },
    [processStreamingMessage],
  )

  const establishConnection = useCallback(
    async (manualReconnect = false) => {
      if (codespaceState !== 'ready') return
      try {
        // Close existing connection before creating a new one
        closeConnection()

        if (manualReconnect) {
          retryCountRef.current = 0
        }

        setConnectionStatus(prev => {
          if (prev === ConnectionStatus.CONNECTED || prev === ConnectionStatus.RECONNECTING) {
            return ConnectionStatus.RECONNECTING
          }

          return ConnectionStatus.CONNECTING
        })
        abortController.current = new AbortController()
        const lastEventTimestamp = events[events.length - 1]?.timestamp
        const res = await fetchFromCodespaceApi(
          `/events${lastEventTimestamp ? `?timestamp=${lastEventTimestamp}` : ''}`,
          {
            signal: abortController.current.signal,
          },
        )

        if (!res.ok) {
          throw new Error(`Failed to connect: ${res.statusText}`)
        }

        hideConnectionErrorBanner()
        setConnectionStatus(ConnectionStatus.CONNECTED)

        retryCountRef.current = 0
        const reader = res.body?.getReader()

        if (reader) {
          responseReader.current = new ServerEventStreamer(reader)
          handleStreamingMessage(responseReader.current)
        }
      } catch (err) {
        if (err instanceof Error && err.name === 'AbortError') {
          return
        }

        handleConnectionErrorRef.current?.(err)
      }
    },
    [closeConnection, codespaceState, events, fetchFromCodespaceApi, handleStreamingMessage, hideConnectionErrorBanner],
  )
  establishConnectionRef.current = establishConnection

  const reconnect = useCallback(() => {
    setConnectionStatus(ConnectionStatus.CONNECTING)
    establishConnectionRef.current?.(true)
  }, [establishConnectionRef])

  const resetHeartbeatCheck = useCallback(() => {
    if (heartbeatCheckRef.current) {
      clearInterval(heartbeatCheckRef.current)
    }

    heartbeatCheckRef.current = setInterval(() => {
      const now = new Date()
      const timeSinceLastEvent = now.getTime() - lastEventTimeRef.current.getTime()

      if (timeSinceLastEvent > 1000 * 30) {
        clearInterval(heartbeatCheckRef.current)
        setConnectionStatus(prev => {
          if (prev === ConnectionStatus.CONNECTED || ConnectionStatus.RECONNECTING) {
            return ConnectionStatus.RECONNECTING
          }

          return ConnectionStatus.CONNECTING
        })
        establishConnectionRef.current?.()
      }
    }, 5000)
  }, [])

  // Add a timer to regularly check heartbeat status
  useEffect(() => {
    if (connectionStatus === ConnectionStatus.CONNECTED) {
      resetHeartbeatCheck()
    }

    return () => {
      if (heartbeatCheckRef.current) {
        clearInterval(heartbeatCheckRef.current)
      }
    }
  }, [closeConnection, establishConnection, connectionStatus, resetHeartbeatCheck])

  useEffect(() => {
    if (codespaceState === 'ready') {
      establishConnectionRef.current?.()
    }

    return closeConnection
  }, [closeConnection, codespaceState])

  // Reset heartbeat check when the window is focused or the document visibility changes. Browsers may pause
  //  JavaScript timers and intervals when a user navigates away from the page, which can cause the heartbeat check
  // to stop running.
  // We can avoid this by proactively resetting the connection when a user returns to the app. We debounce in case
  // the browser emits both `focus` and `visibilitychange` events at the same time.
  const debouncedReconnect = useDebounce(() => {
    if (!reconnectOnFocusEnabled) return
    if (document.visibilityState === 'visible') {
      reconnect()
      resetHeartbeatCheck()
    }
  }, 300)

  useEffect(() => {
    window.addEventListener('focus', debouncedReconnect)
    document.addEventListener('visibilitychange', debouncedReconnect)

    return () => {
      window.removeEventListener('focus', debouncedReconnect)
      document.removeEventListener('visibilitychange', debouncedReconnect)
    }
  }, [debouncedReconnect])

  const value = useMemo(
    () => ({
      isServerConnected:
        connectionStatus === ConnectionStatus.CONNECTED || connectionStatus === ConnectionStatus.RECONNECTING,
      connectionStatus,
      events,
      fetchFromCodespaceApi,
      errors,
      reconnect,
      latestAgentUpdate,
    }),
    [connectionStatus, events, fetchFromCodespaceApi, errors, reconnect, latestAgentUpdate],
  )

  return <ServerEventsContext.Provider value={value}>{children}</ServerEventsContext.Provider>
}

export const useServerEvents = (): ServerEventsContextType => {
  const context = useContext(ServerEventsContext)
  if (context === undefined) {
    throw new Error('useServerEvents must be used within a ServerEventsProvider')
  }
  return context
}

export type {ServerEvent}

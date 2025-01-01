import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import type {ReactNode, SyntheticEvent} from 'react'
import type React from 'react'
import {createContext, useCallback, useContext, useEffect, useMemo, useState} from 'react'

import {useAnalytics} from '../telemetry/use-analytics'
import {useCodespaceContext} from './CodespaceContext'
import {Service, Status, useWorkbenchStore} from './WorkbenchStoreContext'

export const EventType = {
  SPARK_RUNTIME_ERROR: 'sparkRuntimeError',
  SPARK_RUNTIME_PING: 'sparkRuntimePing',
  SPARK_VITE_WS_CONNECT: 'sparkViteWsConnect',
  SPARK_VITE_WS_DISCONNECT: 'sparkViteWsDisconnect',
  SPARK_VITE_ERROR: 'sparkViteError',
  SPARK_VITE_AFTER_UPDATE: 'sparkViteAfterUpdate',
  ROOT_ELEMENT_STATUS: 'rootElementStatus',
} as const

export const ErrorType = {
  BUILD_ERROR: 'buildError',
  RUNTIME_ERROR: 'runtimeError',
} as const

export type ErrorType = (typeof ErrorType)[keyof typeof ErrorType]
export type EventType = (typeof EventType)[keyof typeof EventType]

type RuntimePreviewErrorDetails = {
  column: number
  line: number
  message: string
  path: string
}

export type RuntimePreviewError = {
  type: 'runtimeError'
  error: RuntimePreviewErrorDetails
}

type RuntimeBuildPreviewError = {
  type: 'buildError'
  error: unknown
}

export interface RuntimeError {
  message: string
  path: string
  column?: number
  line?: number
}

export type PreviewError = RuntimePreviewError | RuntimeBuildPreviewError

export interface PreviewState {
  frameContentLoaded: boolean
  pingReceived: boolean
  errorReceived: boolean
  viteWsConnected: boolean
  viteServerReady: boolean
  viteServerConnectionTimedOut: boolean
  viteError: boolean
  viteUpdated: boolean
  rootElementEmpty: boolean
}

export const ANALYTICS_EVENT_NAME = 'preview.state'

export interface WorkbenchPreviewContextType {
  state: PreviewState
  errorQueue: PreviewError[]
  runtimeErrors: RuntimeError[]
  onIFrameLoaded: (event: SyntheticEvent<HTMLIFrameElement>) => void
  addEmptyAppError: () => void
  removeEmptyAppError: () => void
}

export const WorkbenchPreviewContext = createContext<WorkbenchPreviewContextType | undefined>(undefined)

interface WorkbenchPreviewProviderProps {
  children: ReactNode
}

export const WorkbenchPreviewProvider: React.FC<WorkbenchPreviewProviderProps> = ({children}) => {
  const sendEvent = useAnalytics()
  const {codespaceData} = useCodespaceContext()
  const {
    status: {[Service.RUNTIME]: runtimeStatus},
    onConnected,
    onDisconnected,
    onError,
    onSuccess,
  } = useWorkbenchStore()
  const [pollViteServerPort, setPollViteServerPort] = useState(true)

  const [state, setState] = useState<PreviewState>({
    frameContentLoaded: false,
    pingReceived: false,
    errorReceived: false,
    viteServerReady: false,
    viteWsConnected: false,
    viteServerConnectionTimedOut: false,
    viteError: false,
    viteUpdated: false,
    rootElementEmpty: true,
  })

  const [errorQueue, setErrorQueue] = useState<PreviewError[]>([])
  const [runtimeErrors, setRuntimeErrors] = useState<RuntimeError[]>([])

  // Function to update state and emit analytics only if state changed
  const updateStateAndNotify = useCallback(
    (partialState: Partial<PreviewState>) => {
      setState(prevState => {
        const newState = {...prevState, ...partialState}

        // Check if any values actually changed
        const hasChanges = Object.keys(partialState).some(key => {
          const k = key as keyof PreviewState
          return prevState[k] !== partialState[k]
        })

        // Emit analytics only if state changed
        if (hasChanges && copilotFeatureFlags.workbenchPreviewAnalytics) {
          sendEvent(ANALYTICS_EVENT_NAME, {
            state: JSON.stringify(newState),
            timestamp: Date.now(),
          })
        }

        return newState
      })
    },
    [sendEvent],
  )

  // Message event handling
  useEffect(() => {
    function handleMessage(event: MessageEvent) {
      switch (event.data?.type) {
        case EventType.SPARK_RUNTIME_ERROR: {
          updateStateAndNotify({errorReceived: true})
          setErrorQueue(prevQueue => [
            ...prevQueue,
            {
              type: ErrorType.RUNTIME_ERROR,
              error: event.data.payload,
            },
          ])
          onError({service: Service.RUNTIME})
          setRuntimeErrors(prev => [
            ...prev,
            {
              path: event.data.payload.path,
              line: event.data.payload.line,
              column: event.data.payload.column,
              message: event.data.payload.message,
            },
          ])
          break
        }
        case EventType.SPARK_RUNTIME_PING: {
          updateStateAndNotify({pingReceived: true})
          if (runtimeStatus === Status.DISCONNECTED) {
            onConnected({service: Service.RUNTIME})
          }
          break
        }
        case EventType.SPARK_VITE_WS_CONNECT: {
          updateStateAndNotify({viteWsConnected: true, viteServerConnectionTimedOut: false})
          onConnected({service: Service.RUNTIME})
          onConnected({service: Service.VITE})
          onConnected({service: Service.DESIGNER})
          break
        }
        case EventType.SPARK_VITE_WS_DISCONNECT: {
          onConnected({service: Service.RUNTIME})
          onDisconnected({service: Service.VITE})
          onConnected({service: Service.DESIGNER})
          updateStateAndNotify({viteWsConnected: false})
          break
        }
        case EventType.SPARK_VITE_ERROR: {
          updateStateAndNotify({viteError: true})
          onError({service: Service.VITE})
          setErrorQueue(prevQueue => [
            ...prevQueue,
            {
              type: ErrorType.BUILD_ERROR,
              error: event.data.payload,
            },
          ])
          break
        }
        case EventType.SPARK_VITE_AFTER_UPDATE: {
          updateStateAndNotify({viteUpdated: true})
          setRuntimeErrors([])
          onSuccess({service: Service.VITE})
          break
        }
        case EventType.ROOT_ELEMENT_STATUS: {
          const {isEmpty} = event.data.payload
          updateStateAndNotify({rootElementEmpty: isEmpty})
          break
        }
      }
    }
    window.addEventListener('message', handleMessage)

    return () => {
      window.removeEventListener('message', handleMessage)
    }
  }, [updateStateAndNotify, onConnected, onDisconnected, onError, onSuccess, runtimeStatus])

  useEffect(() => {
    let timeoutId: number | null = null

    if (state.frameContentLoaded && !state.viteWsConnected) {
      timeoutId = window.setTimeout(() => {
        setState(prevState => {
          if (!prevState.viteWsConnected) {
            return {...prevState, viteServerConnectionTimedOut: true}
          }
          return prevState
        })
      }, 2000)
    }

    // Reset the flag when Vite connects
    if (state.viteWsConnected) {
      updateStateAndNotify({viteServerConnectionTimedOut: false})
    }

    return () => {
      if (timeoutId !== null) {
        window.clearTimeout(timeoutId)
      }
    }
  }, [state.frameContentLoaded, state.viteWsConnected, updateStateAndNotify])

  // Poll Vite server on port 5000 to check if it's ready
  useEffect(() => {
    if (!pollViteServerPort) return

    const {friendlyName} = codespaceData.codespaceInfo?.environment_data || {}
    const domain = codespaceData.remoteProvider?.tunnelProps.domain ?? 'app.github.dev'
    const tunnelToken = codespaceData.codespaceInfo?.environment_data.connection.tunnelProperties?.connectAccessToken

    if (!friendlyName || !domain || !tunnelToken) {
      return
    }

    let pollInterval: number | null = null

    const checkViteServer = async () => {
      try {
        const baseUrl = `https://${friendlyName}-5000.${domain}`
        const headers = new Headers()
        headers.set('X-Tunnel-Authorization', `tunnel ${tunnelToken}`)

        const response = await fetch(baseUrl, {
          signal: AbortSignal.timeout(500),
          headers,
        })

        if (response.ok) {
          updateStateAndNotify({viteServerReady: true})
          setPollViteServerPort(false)
          if (pollInterval) window.clearInterval(pollInterval)
        }
      } catch {
        // NOOP
      }
    }

    checkViteServer()
    pollInterval = window.setInterval(checkViteServer, 500)

    return () => {
      if (pollInterval) window.clearInterval(pollInterval)
    }
  }, [pollViteServerPort, updateStateAndNotify, codespaceData])

  const emptyAppError: RuntimeError = useMemo(() => {
    return {
      message: `The app is rendering an empty UI.
Please ensure that the App.tsx file returns visible UI components and does not return an empty element like <div></div>.`,
      path: 'src/App.tsx',
    }
  }, [])

  const addEmptyAppError = useCallback(() => {
    setRuntimeErrors(prev => {
      if (prev.some(e => e.message === emptyAppError.message && e.path === emptyAppError.path)) {
        // If the error already exists, do not add it again
        return prev
      }

      return [...prev, emptyAppError]
    })
  }, [emptyAppError])

  const removeEmptyAppError = useCallback(() => {
    setRuntimeErrors(prev => {
      // If not found, do nothing
      if (!prev.some(e => e.message === emptyAppError.message && e.path === emptyAppError.path)) {
        return prev
      }
      return prev.filter(e => e.message !== emptyAppError.message || e.path !== emptyAppError.path)
    })
  }, [emptyAppError])

  const value = useMemo(() => {
    function onIFrameLoaded() {
      updateStateAndNotify({frameContentLoaded: true})
    }

    return {
      state,
      errorQueue,
      runtimeErrors,
      onIFrameLoaded,
      addEmptyAppError,
      removeEmptyAppError,
    }
  }, [state, errorQueue, runtimeErrors, addEmptyAppError, removeEmptyAppError, updateStateAndNotify])

  return <WorkbenchPreviewContext.Provider value={value}>{children}</WorkbenchPreviewContext.Provider>
}

export const useWorkbenchPreview = (): WorkbenchPreviewContextType => {
  const context = useContext(WorkbenchPreviewContext)
  if (context === undefined) {
    throw new Error('useWorkbenchPreview must be used within a WorkbenchPreviewProvider')
  }
  return context
}

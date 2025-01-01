import type {TTelemetryEventName} from '@github-ui/workspace-editor/telemetry/interfaces'
import {createContext, useCallback, useContext, useEffect, useMemo, useState} from 'react'

import {useAnalytics} from '../telemetry/use-analytics'
import type {SparkError} from '../utilities/error'
import {getUniqueErrors, parseRawError} from '../utilities/error'
import {CommandTask} from '../utilities/terminal-reducer'
import {useIterationHistory} from './IterationHistoryContext'
import {usePublishingContext} from './PublishingContext'
import {useServerEvents} from './ServerEventsContext'
import {useTerminalContext} from './TerminalContext'
import {useWorkbenchContext} from './WorkbenchContext'
import {useWorkbenchPreview} from './WorkbenchPreviewContext'

export type ErrorsContextType = {
  editorErrors: SparkError[]
  setEditorErrors: (path: string, errors: SparkError[]) => void
  editorWarnings: SparkError[]
  setEditorWarnings: React.Dispatch<React.SetStateAction<SparkError[]>>
  previewBuildErrors: SparkError[]
  previewRuntimeErrors: SparkError[]
  setPreviewRuntimeErrors: React.Dispatch<React.SetStateAction<SparkError[]>>
  deployBuildErrors: SparkError[]
  setDeployBuildErrors: React.Dispatch<React.SetStateAction<SparkError[]>>
  panelErrors: SparkError[]
  allErrors: SparkError[]
  iterateErrors: SparkError[]
  overlayErrors: SparkError[]
}

export const ErrorsContext = createContext<ErrorsContextType | undefined>(undefined)

export function ErrorsProvider({children}: {children: React.ReactNode}) {
  const {currentRefinementId} = useIterationHistory()
  const {isFetching} = useWorkbenchContext()
  const sendEvent = useAnalytics()
  const sendEventError = useCallback(
    (eventName: TTelemetryEventName, errorMessages: string) => {
      sendEvent(
        eventName,
        currentRefinementId
          ? {
              current_refinement_id: currentRefinementId,
              error_messages: errorMessages,
              timestamp: Date.now(),
            }
          : {
              error_messages: errorMessages,
              timestamp: Date.now(),
            },
      )
    },
    [sendEvent, currentRefinementId],
  )

  /** Handle editor errors */
  const [editorErrors, _setEditorErrors] = useState<SparkError[]>([])
  const setEditorErrors = useCallback((path: string, errors: SparkError[]) => {
    _setEditorErrors(prev => getUniqueErrors([...prev.filter(e => e.path !== path), ...errors]))
  }, [])
  const [editorWarnings, setEditorWarnings] = useState<SparkError[]>([])

  /** preview build errors */
  const [previewBuildErrors, setPreviewBuildErrors] = useState<SparkError[]>([])
  const {events} = useServerEvents()
  useEffect(
    () => {
      if (isFetching) return

      const errors: SparkError[] = []
      for (let i = events.length - 1; i >= 0; i--) {
        const event = events[i]
        if (event?.type === 'build:success' || event?.type === 'agent:succeeded') {
          break
        }
        if (event?.type === 'build:failed' && event.details.error?.message) {
          errors.unshift(parseRawError('preview-build', event.details.error.message))
        }
      }

      const newPreviewBuildErrors = getUniqueErrors(errors)
      setPreviewBuildErrors(newPreviewBuildErrors)
      if (newPreviewBuildErrors.length !== 0)
        sendEventError('errors.preview_build', newPreviewBuildErrors.map(e => e.messageRaw).join('; '))
    },
    // the `sendEvent()` function always changes so we don't want to include it into the dependencies list
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [events, currentRefinementId, isFetching],
  )

  /** preview runtime errors */
  const [previewRuntimeErrors, setPreviewRuntimeErrors] = useState<SparkError[]>([])
  const {runtimeErrors} = useWorkbenchPreview()
  useEffect(
    () => {
      if (isFetching) return

      const newPreviewRuntimeErrors = getUniqueErrors(
        runtimeErrors.map(e => parseRawError('preview-runtime', e.message)),
      )
      setPreviewRuntimeErrors(newPreviewRuntimeErrors)
      if (newPreviewRuntimeErrors.length !== 0)
        sendEventError('errors.preview_runtime', runtimeErrors.map(e => e.message).join('; '))
    },
    // the `sendEvent()` function always changes so we don't want to include it into the dependencies list
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [runtimeErrors, currentRefinementId, isFetching],
  )

  useEffect(() => {
    const lastEvent = events[events.length - 1]
    if (lastEvent?.type === 'build:success' || lastEvent?.type === 'agent:succeeded') setPreviewRuntimeErrors([])
  }, [events])

  /** deploy build errors */
  const {publishingStatus} = usePublishingContext()
  const {state} = useTerminalContext()
  const {output} = state.history[CommandTask.Deploy]
  const [deployBuildErrors, setDeployBuildErrors] = useState<SparkError[]>([])
  useEffect(
    () => {
      if (publishingStatus !== 'unpublished' && publishingStatus !== 'republishFailed') {
        setDeployBuildErrors([])
        return
      }

      const lines = output.split('\n')
      // Find the first line containing the word "error" (case insensitive)
      const errorIndex = lines.findIndex(line => line.toLowerCase().includes('error'))

      if (errorIndex === -1) {
        setDeployBuildErrors([])
        return
      }

      // Collect the error line and all following lines
      const errorMessage = lines
        .slice(errorIndex)
        .filter(line => line.length !== 0)
        .join('\n')

      if (!errorMessage.trim()) {
        setDeployBuildErrors([])
        return
      }

      const newDeployBuildErrors = [parseRawError('deploy', errorMessage)]
      setDeployBuildErrors(newDeployBuildErrors)
      if (newDeployBuildErrors.length !== 0)
        sendEventError('errors.deploy_build', newDeployBuildErrors.map(e => e.messageRaw).join('; '))
    },
    // the `sendEvent()` function always changes so we don't want to include it into the dependencies list
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [output, currentRefinementId, publishingStatus],
  )

  /** Misc helpers */
  const allErrors: SparkError[] = useMemo(
    () => [...editorErrors, ...previewBuildErrors, ...previewRuntimeErrors, ...deployBuildErrors],
    [deployBuildErrors, editorErrors, previewRuntimeErrors, previewBuildErrors],
  )

  const iterateErrors: SparkError[] = useMemo(
    () => [...previewBuildErrors, ...previewRuntimeErrors, ...deployBuildErrors].slice(0, 3),
    [deployBuildErrors, previewRuntimeErrors, previewBuildErrors],
  )

  const overlayErrors: SparkError[] = useMemo(
    () =>
      [...previewBuildErrors, ...previewRuntimeErrors]
        .filter(
          error =>
            error.messageRaw !==
              "Runtime error: Uncaught TypeError: Cannot read properties of null (reading 'useContext')" &&
            error.messageRaw !==
              "Runtime error: Uncaught TypeError: Cannot read properties of null (reading 'useState')",
        )
        .slice(0, 1),
    [previewBuildErrors, previewRuntimeErrors],
  )

  /** Depricated, iterate panel is no longer used */
  const panelErrors: SparkError[] = useMemo(
    () => [...previewBuildErrors, ...deployBuildErrors, ...previewRuntimeErrors],
    [deployBuildErrors, previewBuildErrors, previewRuntimeErrors],
  )

  const contextValue = useMemo(
    () => ({
      editorErrors,
      setEditorErrors,
      editorWarnings,
      setEditorWarnings,
      previewBuildErrors,
      previewRuntimeErrors,
      setPreviewRuntimeErrors,
      deployBuildErrors,
      setDeployBuildErrors,
      panelErrors,
      allErrors,
      iterateErrors,
      overlayErrors,
    }),
    [
      editorErrors,
      setEditorErrors,
      editorWarnings,
      setEditorWarnings,
      previewBuildErrors,
      previewRuntimeErrors,
      setPreviewRuntimeErrors,
      deployBuildErrors,
      setDeployBuildErrors,
      panelErrors,
      allErrors,
      iterateErrors,
      overlayErrors,
    ],
  )
  return <ErrorsContext.Provider value={contextValue}>{children}</ErrorsContext.Provider>
}

export function useErrors() {
  const context = useContext(ErrorsContext)
  if (!context) {
    throw new Error('useErrors must be used within an ErrorsProvider')
  }
  return context
}

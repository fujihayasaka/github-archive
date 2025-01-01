import type {CopilotChatRepo} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {DetailsDialog} from '@github-ui/workspace-editor/components/DetailsDialog'
import {AnalyticsContext} from '@github-ui/workspace-editor/telemetry/AnalyticsContext'
import {UNKNOWN_VALUE} from '@github-ui/workspace-editor/telemetry/constants'
import {clsx} from 'clsx'
import {useCallback, useEffect, useRef, useState} from 'react'

import {TerminalPanel} from '../components/TerminalPanel'
import {useTerminalContext} from '../contexts/TerminalContext'
import {useWorkbenchUI} from '../contexts/WorkbenchUIContext'
import type {UseWorkbenchReturn} from '../hooks/use-workbench'
import {useAnalytics} from '../telemetry/use-analytics'
import type {WorkbenchRoutePayload} from '../types/workbench-types'
import {Editor} from './Editor'
import styles from './MainContent.module.css'
import {PreviewArea} from './PreviewArea/PreviewArea'

/**
 * MainContent component for the Workbench Editor app.
 * Displays the file tree, editor, and terminal.
 */

// Animation states for the panels
type AnimationState = 'entering' | 'exiting' | 'idle' | 'hidden'

export function MainContent({
  copilotCurrentTopic,
  workbenchData,
}: {
  copilotCurrentTopic: CopilotChatRepo
  workbenchData: UseWorkbenchReturn
}) {
  const payload = useRoutePayload<WorkbenchRoutePayload>()
  const {
    state: {isCollapsed, codespaceData},
    dispatch,
  } = useTerminalContext()

  const ANIMATION_DURATION = 300 // ms - same as in CSS

  const {isFetching} = workbenchData
  const {workingMode} = useWorkbenchUI()
  const previewContainerRef = useRef<HTMLDivElement>(null)

  const [detailsDialogVisibility, setDetailsDialogVisibility] = useState<'visible' | 'hidden'>('hidden')
  const [isRefreshing, setIsRefreshing] = useState(false)
  const [codeViewState, setCodeViewState] = useState<AnimationState>(workingMode === 'preview' ? 'hidden' : 'idle')
  const [previewState, setPreviewState] = useState<AnimationState>(workingMode === 'code' ? 'hidden' : 'idle')

  const timeoutIds = useRef<NodeJS.Timeout[]>([])

  const sendEvent = useAnalytics()

  const onTerminalButtonClick = useCallback(() => {
    // the `terminalVisibility` will be inverted below, so
    // we depend on the `Hidden` value here
    if (isCollapsed) {
      sendEvent('terminal.open', {
        is_new: UNKNOWN_VALUE,
        is_connected: UNKNOWN_VALUE,
        codespace_state: codespaceData.codespaceState,
      })
    }
    dispatch({type: 'TOGGLE_TERMINAL_IS_COLLAPSED', isCollapsed: !isCollapsed})
  }, [codespaceData.codespaceState, sendEvent, dispatch, isCollapsed])

  const onDetailsClick = useCallback(() => {
    setDetailsDialogVisibility(visibility => (visibility === 'visible' ? 'hidden' : 'visible'))
  }, [])

  // Create telemetry context metadata for the validation.
  const validationMetadata = useCallback(() => {
    return {
      session_id: UNKNOWN_VALUE,
    }
  }, [])

  // Remove spin after animation completes (1s)
  useEffect(() => {
    if (isRefreshing) {
      const timeout = setTimeout(() => setIsRefreshing(false), 1000)
      return () => clearTimeout(timeout)
    }
  }, [isRefreshing])

  // Remove the DOM class manipulation for animation
  // This effect is no longer needed and has been removed

  // Handle animations when workingMode changes
  useEffect(() => {
    // Set up the animations
    if (workingMode === 'preview' && codeViewState !== 'hidden' && codeViewState !== 'exiting') {
      setCodeViewState('exiting')
    } else if (workingMode !== 'preview' && codeViewState === 'hidden') {
      setCodeViewState('entering')
    }

    if (workingMode === 'code' && previewState !== 'hidden' && previewState !== 'exiting') {
      setPreviewState('exiting')
    } else if (workingMode !== 'code' && previewState === 'hidden') {
      setPreviewState('entering')
    }

    // Clean up all timeouts
    const timeouts = timeoutIds.current
    return () => {
      for (const id of timeouts) {
        clearTimeout(id)
      }
    }
  }, [workingMode, codeViewState, previewState])

  useEffect(() => {
    if (codeViewState === 'exiting') {
      const timeout = setTimeout(() => setCodeViewState('hidden'), ANIMATION_DURATION)
      timeoutIds.current.push(timeout)
    } else if (codeViewState === 'entering') {
      const timeout = setTimeout(() => setCodeViewState('idle'), ANIMATION_DURATION)
      timeoutIds.current.push(timeout)
    }
  }, [codeViewState, workingMode])

  useEffect(() => {
    if (previewState === 'exiting') {
      const timeout = setTimeout(() => setPreviewState('hidden'), ANIMATION_DURATION)
      timeoutIds.current.push(timeout)
    } else if (previewState === 'entering') {
      const timeout = setTimeout(() => setPreviewState('idle'), ANIMATION_DURATION)
      timeoutIds.current.push(timeout)
    }
  }, [previewState, workingMode])

  // Build class names with animation states and scaling
  const codeViewClassName = clsx(
    styles.editorAndTerminal,
    codeViewState === 'entering' && styles.codeViewEntering,
    codeViewState === 'exiting' && styles.codeViewExiting,
    workingMode === 'split' && styles.halfWidth,
    workingMode === 'code' && styles.fullWidth,
  )

  // Build class names for preview container
  const previewClassName = clsx(
    styles.previewContainer,
    // Width classes for regular view
    workingMode === 'split' && styles.halfWidth,
    workingMode === 'preview' && styles.fullWidth,
    // Panel transitions without fullscreen
    previewState === 'entering' && styles.previewEntering,
    previewState === 'exiting' && styles.previewExiting,
  )

  return (
    <>
      <div className={styles.container}>
        <div className={styles.contentContainer}>
          <div className={codeViewClassName}>
            <div className={clsx(styles.editorContainer, codeViewState !== 'hidden' && styles.visibleContainer)}>
              <Editor
                copilotAccessAllowed={payload.copilotAccessAllowed}
                copilotCurrentTopic={copilotCurrentTopic}
                codespaceData={codespaceData}
                remoteProvider={codespaceData.remoteProvider}
                onTerminalClick={onTerminalButtonClick}
              />
            </div>
            {copilotFeatureFlags.workbenchTerminal && (
              <AnalyticsContext name="validation" metadata={validationMetadata}>
                <TerminalPanel onDetailsClick={onDetailsClick} onTerminalClick={onTerminalButtonClick} />
              </AnalyticsContext>
            )}
          </div>

          <div
            ref={previewContainerRef}
            className={clsx(previewClassName, previewState !== 'hidden' && styles.visibleContainer)}
          >
            <PreviewArea isFetching={isFetching} />
          </div>
        </div>
      </div>

      <DetailsDialog
        detailsDialogVisibility={detailsDialogVisibility}
        onDetailsClick={onDetailsClick}
        codespaceData={codespaceData}
      />
    </>
  )
}

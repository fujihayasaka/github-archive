import type {CopilotChatRepo} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useTreePane} from '@github-ui/repos-file-tree-view'
import {Box} from '@primer/react'
import {useCallback, useState} from 'react'

import {Editor} from '../components/Editor'
import {FileTree} from '../components/FileTree'
import {TerminalPanel} from '../components/TerminalPanel'
import {useTerminalContext} from '../contexts/TerminalContext'
import {useWorkspaceEditorUIState} from '../contexts/WorkspaceEditorUIContext'
import {useObjectWrapper} from '../hooks/use-object-wrapper'
import {AnalyticsContext} from '../telemetry/AnalyticsContext'
import {UNKNOWN_VALUE} from '../telemetry/constants'
import {useAnalytics} from '../telemetry/use-analytics'
import {setTreeExpanded} from '../utilities/preferences'
import type {WorkspaceEditorRoutePayload} from '../utilities/workspace-editor-types'
import {DetailsDialog} from './DetailsDialog'
import styles from './MainContent.module.css'
import {OverviewContent} from './overview/OverviewContent'

/**
 * MainContent component for the Workspace Editor app.
 * Displays the file tree, editor, and terminal.
 */
export function MainContent({copilotCurrentTopic}: {copilotCurrentTopic: CopilotChatRepo}) {
  const payload = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {
    state: {isCollapsed, codespaceData},
    dispatch,
  } = useTerminalContext()
  const {rightPanel} = useWorkspaceEditorUIState()

  const [detailsDialogVisibility, setDetailsDialogVisibility] = useState<'visible' | 'hidden'>('hidden')

  const fileTreeId = 'repos-file-tree'
  const openFileTreePaneRef = useObjectWrapper(rightPanel)

  const textAreaId = 'text-area-id' // TODO: replace with actual text area id
  const treePaneProps = useTreePane(
    fileTreeId,
    openFileTreePaneRef,
    payload.treeExpanded ?? true,
    textAreaId, // TODO: replace with actual text area id
    setTreeExpanded,
    '',
    {useFilesButtonBreakpoint: false, getTooltipDirection: expanded => (expanded ? 'sw' : 'se')},
  )
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

  return (
    <Box
      sx={{
        display: 'flex',
        border: '1px solid',
        borderColor: 'border.default',
        borderRadius: 2,
        bg: 'canvas.default',
        overflow: 'hidden',
        boxShadow: 2,
        height: 'var(--workspace-editor-content-height)',
      }}
    >
      <div className={treePaneProps.isTreeExpanded ? styles.treeContainerExpanded : styles.treeContainerCollapsed}>
        <FileTree {...treePaneProps} textAreaId={textAreaId} treeToggleElement={treePaneProps.treeToggleElement} />
      </div>
      <div className={styles.editorAndTerminalContainer}>
        {payload.showOverview ? (
          <OverviewContent
            codespaceData={codespaceData}
            isTreeExpanded={treePaneProps.isTreeExpanded}
            onTerminalClick={onTerminalButtonClick}
            treeToggleElement={treePaneProps.treeToggleElement}
            onDetailsClick={onDetailsClick}
          />
        ) : (
          <div className={styles.editorContainer}>
            <Editor
              copilotAccessAllowed={payload.copilotAccessAllowed}
              copilotCurrentTopic={copilotCurrentTopic}
              codespaceData={codespaceData}
              isTreeExpanded={treePaneProps.isTreeExpanded}
              remoteProvider={codespaceData.remoteProvider}
              treeToggleElement={treePaneProps.treeToggleElement}
              onTerminalClick={onTerminalButtonClick}
              onDetailsClick={onDetailsClick}
            />
          </div>
        )}
        <AnalyticsContext name="validation" metadata={validationMetadata}>
          <TerminalPanel onDetailsClick={onDetailsClick} onTerminalClick={onTerminalButtonClick} />
        </AnalyticsContext>
      </div>
      <DetailsDialog
        detailsDialogVisibility={detailsDialogVisibility}
        onDetailsClick={onDetailsClick}
        codespaceData={codespaceData}
      />
    </Box>
  )
}

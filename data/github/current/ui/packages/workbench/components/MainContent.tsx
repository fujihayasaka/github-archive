import type {CopilotChatRepo} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useTreePane} from '@github-ui/repos-file-tree-view'
import {useNavigate} from '@github-ui/use-navigate'
import {FileIcon} from '@primer/octicons-react'
import {TreeView} from '@primer/react'
import {useCallback, useEffect, useState} from 'react'

import {DetailsDialog} from '../../workspace-editor/components/DetailsDialog'
import {useWorkspaceEditorUIState} from '../../workspace-editor/contexts/WorkspaceEditorUIContext'
import {useObjectWrapper} from '../../workspace-editor/hooks/use-object-wrapper'
import {AnalyticsContext} from '../../workspace-editor/telemetry/AnalyticsContext'
import {UNKNOWN_VALUE} from '../../workspace-editor/telemetry/constants'
import {useAnalytics} from '../../workspace-editor/telemetry/use-analytics'
import {setTreeExpanded} from '../../workspace-editor/utilities/preferences'
import {TerminalPanel} from '../components/TerminalPanel'
import {useTerminalContext} from '../contexts/TerminalContext'
import type {WorkbenchRoutePayload} from '../types/workbench-types'
import {sparkFileUrl} from '../utilities/urls'
import {Editor} from './Editor'
import styles from './MainContent.module.css'
import {PreviewAreaComponent} from './PreviewAreaComponent'

/**
 * MainContent component for the Workbench Editor app.
 * Displays the file tree, editor, and terminal.
 */

export function MainContent({copilotCurrentTopic}: {copilotCurrentTopic: CopilotChatRepo}) {
  const payload = useRoutePayload<WorkbenchRoutePayload>()
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

  const navigate = useNavigate()
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const handleSelection = (e: any) => {
    navigate(sparkFileUrl({sparkId: payload.workbench.id, path: e.target.closest('li').id}))
  }

  // TODO: Figure out why the default view without file directly selected throws errors
  // Until then navigate to index.html by default.
  useEffect(() => {
    const path = window.location.pathname
    if (path.startsWith('/copilot/spark') && !path.includes('file')) {
      navigate(sparkFileUrl({sparkId: payload.workbench.id, path: 'index.html'}))
    }
  })

  return (
    <div className={styles.container}>
      <div className={styles.sidebar}>
        <div className={styles.treeView}>
          <TreeView aria-label="Files changed">
            <TreeView.Item id="src" defaultExpanded>
              <TreeView.LeadingVisual>
                <TreeView.DirectoryIcon />
              </TreeView.LeadingVisual>
              src
              <TreeView.SubTree>
                <TreeView.Item onSelect={handleSelection} id="src/App.tsx">
                  <TreeView.LeadingVisual>
                    <FileIcon />
                  </TreeView.LeadingVisual>
                  App.tsx
                </TreeView.Item>
                <TreeView.Item onSelect={handleSelection} id="src/index.css">
                  <TreeView.LeadingVisual>
                    <FileIcon />
                  </TreeView.LeadingVisual>
                  index.css
                </TreeView.Item>
              </TreeView.SubTree>
            </TreeView.Item>
            <TreeView.Item onSelect={handleSelection} id="index.html">
              <TreeView.LeadingVisual>
                <FileIcon />
              </TreeView.LeadingVisual>
              index.html
            </TreeView.Item>
          </TreeView>
          {/* <FileTree {...treePaneProps} textAreaId={textAreaId} treeToggleElement={treePaneProps.treeToggleElement} /> */}
        </div>
      </div>

      <div className={styles.editorAndTerminal}>
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
        <AnalyticsContext name="validation" metadata={validationMetadata}>
          <TerminalPanel onDetailsClick={onDetailsClick} onTerminalClick={onTerminalButtonClick} />
        </AnalyticsContext>
      </div>
      <div className={styles.preview}>
        <PreviewAreaComponent codespaceData={codespaceData} />
      </div>
      <DetailsDialog
        detailsDialogVisibility={detailsDialogVisibility}
        onDetailsClick={onDetailsClick}
        codespaceData={codespaceData}
      />
    </div>
  )
}

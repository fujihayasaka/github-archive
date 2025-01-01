import 'xterm/css/xterm.css'

import {UnderlinePanels} from '@primer/react/experimental'
import {clsx} from 'clsx'
import {useCallback, useEffect, useRef} from 'react'

import {TerminalHeader} from '../../workspace-editor/components/TerminalHeader'
import type {Pane} from '../../workspace-editor/utilities/terminal-reducer'
import {Terminal} from '../components/Terminal'
import {useTerminalContext} from '../contexts/TerminalContext'
import {DeploymentOutput} from './Deployment/DeploymentOutput'
import styles from './TerminalPanel.module.css'

interface ITerminalPanelProps {
  onDetailsClick: () => void
  onTerminalClick: () => void
}

export function TerminalPanel({onDetailsClick, onTerminalClick}: ITerminalPanelProps): JSX.Element {
  const collapseButtonRef = useRef<HTMLButtonElement>(null)
  const terminalPaneRef = useRef<HTMLDivElement>(null)

  const {
    dispatch: terminalDispatch,
    state: {isCollapsed, pane, codespaceData},
  } = useTerminalContext()

  // Open or close the terminal
  const onTerminalVisibilityChange = useCallback(() => {
    terminalDispatch({
      type: 'TOGGLE_TERMINAL_IS_COLLAPSED',
      isCollapsed: !isCollapsed,
    })
  }, [isCollapsed, terminalDispatch])

  // Clicking on any tab should open the terminal when its collapsed. Clicking on the open tab will
  // collapse the panel.
  const onTabClick = useCallback(
    (selectedPane: Pane) => {
      terminalDispatch({type: 'TOGGLE_TERMINAL_PANE', pane: selectedPane})

      if (isCollapsed) {
        terminalDispatch({
          type: 'TOGGLE_TERMINAL_IS_COLLAPSED',
          isCollapsed: !isCollapsed,
        })
      } else if (pane === selectedPane) {
        terminalDispatch({
          type: 'TOGGLE_TERMINAL_IS_COLLAPSED',
          isCollapsed: !isCollapsed,
        })
      }
    },
    [isCollapsed, terminalDispatch, pane],
  )

  // Detect change in visibility
  useEffect(() => {
    if (!isCollapsed) {
      collapseButtonRef.current?.focus()
    }
  }, [terminalDispatch, isCollapsed, pane])

  // Telemetry events for pane changes

  // If the panel is open when the codespace leaves the ready state, close it
  useEffect(() => {
    if (!isCollapsed && codespaceData.codespaceState !== 'ready') {
      onTerminalVisibilityChange()
    }
  }, [codespaceData.codespaceState, isCollapsed, onTerminalVisibilityChange])

  return (
    <div className={clsx(styles.terminalPanel, isCollapsed ? styles.collapsed : '')}>
      <TerminalHeader
        collapseButtonRef={collapseButtonRef}
        onDetailsClick={onDetailsClick}
        isRecoveryContainer={codespaceData.isRecoveryContainer}
        codespaceData={codespaceData}
        onTerminalClick={onTerminalClick}
        onTerminalVisibilityChange={() => onTerminalVisibilityChange()}
        isCollapsed={isCollapsed}
      />

      <UnderlinePanels
        aria-label="Select a tab"
        sx={{
          borderTop: '1px solid',
          borderColor: 'border.default',
        }}
      >
        <UnderlinePanels.Tab
          aria-selected={pane === 'output'}
          onSelect={() => {
            onTabClick('output')
          }}
        >
          Deployment
        </UnderlinePanels.Tab>
        <UnderlinePanels.Tab
          aria-selected={pane === 'terminal'}
          onSelect={() => {
            onTabClick('terminal')
          }}
        >
          Terminal
        </UnderlinePanels.Tab>

        <UnderlinePanels.Panel sx={{height: 'var(--workspace-editor-terminal-pane-height)', overflowY: 'auto'}} hidden>
          <DeploymentOutput />
        </UnderlinePanels.Panel>
        <UnderlinePanels.Panel sx={{height: 'var(--workspace-editor-terminal-pane-height)', overflowY: 'hidden'}}>
          <Terminal terminalRef={terminalPaneRef} />
        </UnderlinePanels.Panel>
      </UnderlinePanels>
    </div>
  )
}

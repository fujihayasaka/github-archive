import 'xterm/css/xterm.css'

import {TerminalHeader} from '@github-ui/workspace-editor/components/TerminalHeader'
import {UnderlinePanels} from '@primer/react/experimental'
import {clsx} from 'clsx'
import {useCallback, useEffect, useRef} from 'react'

import {Terminal} from '../components/Terminal'
import {useTerminalContext} from '../contexts/TerminalContext'
import type {Pane} from '../utilities/terminal-reducer'
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
      <UnderlinePanels id="workbench-terminal-tabs" aria-label="Select a tab" className={styles.UnderlinePanels}>
        <UnderlinePanels.Tab
          aria-selected={pane === 'terminal'}
          onSelect={() => {
            onTabClick('terminal')
          }}
        >
          Terminal
        </UnderlinePanels.Tab>
        <UnderlinePanels.Tab
          aria-selected={pane === 'output'}
          onSelect={() => {
            onTabClick('output')
          }}
        >
          Deployment
        </UnderlinePanels.Tab>
        <UnderlinePanels.Panel className={styles.PanelHidden}>
          <Terminal terminalRef={terminalPaneRef} />
        </UnderlinePanels.Panel>
        <UnderlinePanels.Panel className={styles.Panel} hidden>
          <DeploymentOutput />
        </UnderlinePanels.Panel>
      </UnderlinePanels>
    </div>
  )
}

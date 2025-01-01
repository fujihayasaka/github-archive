import 'xterm/css/xterm.css'

import {UnderlinePanels} from '@primer/react/experimental'
import {clsx} from 'clsx'
import {useCallback, useEffect, useRef} from 'react'

import {useTerminalContext} from '../contexts/TerminalContext'
import {useAnalytics} from '../telemetry/use-analytics'
import type {Pane} from '../utilities/terminal-reducer'
import {Terminal} from './Terminal'
import {TerminalHeader} from './TerminalHeader'
import {TerminalOutputPanel} from './TerminalOutputPanel'
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

  const sendEvent = useAnalytics()

  // Telemetry events for pane changes
  useEffect(
    () => {
      if (!isCollapsed) {
        if (pane === 'terminal') {
          sendEvent('validation.terminal.open')
        } else if (pane === 'output') {
          sendEvent('validation.output.open')
        }
      }
    },
    // the `sendEvent()` function always changes so we don't want to include it into the dependencies list
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [pane, isCollapsed],
  )

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

      <UnderlinePanels aria-label="Select a tab" className="border-top">
        <UnderlinePanels.Tab
          aria-selected={pane === 'output'}
          onSelect={() => {
            onTabClick('output')
          }}
        >
          Output
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
          <TerminalOutputPanel />
        </UnderlinePanels.Panel>
        <UnderlinePanels.Panel sx={{height: 'var(--workspace-editor-terminal-pane-height)', overflowY: 'hidden'}}>
          <Terminal terminalRef={terminalPaneRef} />
        </UnderlinePanels.Panel>
      </UnderlinePanels>
    </div>
  )
}

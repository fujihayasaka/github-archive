import 'xterm/css/xterm.css'

import {UnderlinePanels} from '@primer/react/experimental'
import {useCallback, useEffect, useRef} from 'react'

import {useTerminalContext} from '../contexts/TerminalContext'
import {useAnalytics} from '../telemetry/use-analytics'
import {OutputPane} from './OutputPane'
import {Terminal} from './Terminal'
import {TerminalHeader} from './TerminalHeader'
import styles from './TerminalPanel.module.css'

interface ITerminalPanelProps {
  onDetailsClick: () => void
}

export function TerminalPanel({onDetailsClick}: ITerminalPanelProps): JSX.Element {
  const closeButtonRef = useRef<HTMLButtonElement>(null)
  const terminalPaneRef = useRef<HTMLDivElement>(null)

  const {
    dispatch: terminalDispatch,
    state: {terminalVisibility, pane, codespaceData},
  } = useTerminalContext()

  const onTerminalVisibilityChange = useCallback(() => {
    const visibility = terminalVisibility === 'visible' ? 'hidden' : 'visible'
    terminalDispatch({
      type: 'TOGGLE_TERMINAL_VISIBILITY',
      terminalVisibility: visibility,
    })
  }, [terminalVisibility, terminalDispatch])

  const isCodespaceReady = codespaceData.codespaceState === 'ready'

  // Detect change in visibility
  useEffect(() => {
    if (terminalVisibility === 'visible') {
      closeButtonRef.current?.focus()
    }
  }, [terminalDispatch, terminalVisibility])

  useEffect(() => {
    if (terminalVisibility === 'hidden') {
      return
    }

    const observer = new IntersectionObserver(([entry]) => {
      const panelVisible = entry?.isIntersecting
      const visiblePane = panelVisible ? 'terminal' : 'output'
      terminalDispatch({type: 'TOGGLE_TERMINAL_PANE', pane: visiblePane})
    })

    const terminalPane = terminalPaneRef.current
    if (terminalPane) {
      observer.observe(terminalPane)
    }

    return () => {
      if (terminalPane) {
        observer.unobserve(terminalPane)
      }
    }
  }, [terminalDispatch, terminalVisibility])

  const sendEvent = useAnalytics()
  // Telemetry events for pane changes
  useEffect(
    () => {
      if (terminalVisibility === 'visible') {
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
    [pane, terminalVisibility],
  )
  // If the panel is open when the codespace leaves the ready state, close it
  useEffect(() => {
    if (terminalVisibility === 'visible' && codespaceData.codespaceState !== 'ready') {
      onTerminalVisibilityChange()
    }
  }, [codespaceData.codespaceState, terminalVisibility, onTerminalVisibilityChange])

  if (terminalVisibility === 'hidden') {
    return <></>
  }

  return (
    <div className={styles.terminalPanel}>
      <TerminalHeader
        closeButtonRef={closeButtonRef}
        onTerminalVisibilityChange={onTerminalVisibilityChange}
        onDetailsClick={onDetailsClick}
        isRecoveryContainer={codespaceData.isRecoveryContainer}
      />
      <UnderlinePanels
        aria-label="Select a tab"
        sx={{
          borderTop: '1px solid',
          borderColor: 'border.default',
        }}
      >
        <UnderlinePanels.Tab aria-selected={pane === 'output'}>Output</UnderlinePanels.Tab>
        <UnderlinePanels.Tab aria-selected={pane === 'terminal'}>Terminal</UnderlinePanels.Tab>
        <UnderlinePanels.Panel sx={{height: 'var(--workspace-editor-terminal-pane-height)', overflowY: 'auto'}}>
          <OutputPane onTerminalVisibilityChange={onTerminalVisibilityChange} isCodespaceReady={isCodespaceReady} />
        </UnderlinePanels.Panel>
        <UnderlinePanels.Panel
          sx={{height: 'var(--workspace-editor-terminal-pane-height)', overflowY: 'hidden'}}
          hidden
        >
          <Terminal terminalRef={terminalPaneRef} />
        </UnderlinePanels.Panel>
      </UnderlinePanels>
    </div>
  )
}

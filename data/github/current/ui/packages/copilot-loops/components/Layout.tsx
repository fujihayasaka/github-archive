import {useState} from 'react'
import {clsx} from 'clsx'
import {IconButton, useResizeObserver} from '@primer/react'
import {HistoryIcon} from '@primer/octicons-react'
import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {sendEvent} from '@github-ui/hydro-analytics'

import {Canvas} from './Canvas'
import {ComponentErrorBoundary} from './ComponentErrorBoundary'
import {Header} from './Header'
import styles from './Layout.module.css'
import {LoopPlaceholder} from './LoopPlaceholder'
import {usePipesStateLens, usePipesDispatch} from '../contexts/PipesStateProvider'
import {SidePanel} from './SidePanel'
import {useLoop} from '../hooks/queries/use-loop'

const MOBILE_BREAKPOINT = 1024

export function Layout() {
  const {data: loop} = useLoop()
  const hasCurrentPipeline = !!loop
  const selectedNodeId = usePipesStateLens(s => s.uiState.focusedNodeId)
  const pipelineId = loop?.id
  const dispatch = usePipesDispatch()
  const [isPanelOpen, setIsPanelOpen] = useState(false)
  const {streamingMessage, isWaitingOnCopilot} = useChatState()
  const showLoopPlaceholder = streamingMessage || isWaitingOnCopilot
  const [isMobileView, setIsMobileView] = useState(() => {
    return typeof window !== 'undefined' && window.innerWidth < MOBILE_BREAKPOINT
  })

  useResizeObserver(() => {
    setIsMobileView(window.innerWidth < MOBILE_BREAKPOINT)
  })

  const hasSelectedNode = !!selectedNodeId && !!pipelineId
  const isPanelVisible = !isMobileView || isPanelOpen || hasSelectedNode

  const closePanel = () => {
    dispatch({type: 'FOCUS_NODE', nodeId: null})
    if (isMobileView) setIsPanelOpen(false)
  }

  const togglePanel = () => {
    sendEvent('dotcom_chat.activate', {
      target: isPanelOpen ? 'PANEL_MOBILE_CLOSE' : 'PANEL_MOBILE_OPEN',
      mode: 'loops',
    })
    setIsPanelOpen(!isPanelOpen)
  }

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <Header />
      </div>
      <div className={styles.main}>
        {isMobileView && (
          <IconButton
            className={styles.panelToggleButton}
            onClick={togglePanel}
            icon={HistoryIcon}
            aria-label={isPanelOpen ? 'Close panel' : 'Open panel'}
            aria-expanded={isPanelOpen}
          />
        )}
        {/* eslint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions */}
        {isMobileView && isPanelVisible && <div className={styles.backdrop} onClick={closePanel} />}
        <div className={clsx(styles.panel, {[styles.visible]: isPanelVisible})}>
          <div className={styles.scrollContainer}>
            <ComponentErrorBoundary name="side-panel">
              <SidePanel isMobileView={isMobileView} nodeId={selectedNodeId} pipelineId={pipelineId} />
            </ComponentErrorBoundary>
          </div>
        </div>
        <div className={styles.canvas}>
          {showLoopPlaceholder ? (
            <LoopPlaceholder />
          ) : hasCurrentPipeline ? (
            <ComponentErrorBoundary name="canvas">
              <Canvas />
            </ComponentErrorBoundary>
          ) : null}
        </div>
      </div>
    </div>
  )
}

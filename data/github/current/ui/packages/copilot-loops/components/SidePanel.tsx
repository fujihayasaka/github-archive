import {useState, useEffect} from 'react'
import {SegmentedControl} from '@primer/react'
import {CommentIcon, GearIcon} from '@primer/octicons-react'
import {sendEvent} from '@github-ui/hydro-analytics'
import {CompactNodePanel} from './nodes/compact/CompactNodePanel'
import {ChatMessages} from './chat/ChatMessages'
import {NodeIcon} from '@github-ui/pacer/CustomIcon'
import styles from './SidePanel.module.css'
import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {ConfigurePanel} from './ConfigurePanel'

interface SidePanelProps {
  isMobileView: boolean
  nodeId?: string | null
  pipelineId?: string | null
}

export function SidePanel({isMobileView, nodeId, pipelineId}: SidePanelProps) {
  const {streamingMessage, isWaitingOnCopilot} = useChatState()
  const isStreaming = streamingMessage || isWaitingOnCopilot
  const [activeView, setActiveView] = useState<'chat' | 'node' | 'configure'>(isStreaming ? 'chat' : 'node')

  useEffect(() => {
    if (isStreaming) {
      setActiveView('chat')
    }
  }, [isStreaming])

  useEffect(() => {
    if (nodeId && !isStreaming) {
      setActiveView('node')
    }
  }, [isStreaming, nodeId])

  const handleViewChange = (index: number) => {
    let newView: 'chat' | 'node' | 'configure'
    let target: string

    if (index === 0) {
      newView = 'chat'
      target = 'PANEL_SELECT_CHAT'
    } else if (index === 1) {
      newView = 'node'
      target = 'PANEL_SELECT_NODE'
    } else {
      newView = 'configure'
      target = 'PANEL_SELECT_CONFIGURE'
    }

    setActiveView(newView)
    sendEvent('dotcom_chat.activate', {
      target,
      mode: 'loops',
    })
  }

  return (
    <div className={styles.container}>
      <div className={styles.panelHeader}>
        <SegmentedControl aria-label="Loops panel" className={styles.segmentedControl} onChange={handleViewChange}>
          <SegmentedControl.Button selected={activeView === 'chat'} leadingIcon={CommentIcon}>
            Refine
          </SegmentedControl.Button>
          <SegmentedControl.Button selected={activeView === 'node'} leadingIcon={NodeIcon}>
            Node
          </SegmentedControl.Button>
          <SegmentedControl.Button selected={activeView === 'configure'} leadingIcon={GearIcon}>
            Configure
          </SegmentedControl.Button>
        </SegmentedControl>
      </div>
      <div className={styles.content}>
        {activeView === 'node' ? (
          <CompactNodePanel key={nodeId || 'empty'} pipelineId={pipelineId} nodeId={nodeId} />
        ) : activeView === 'chat' ? (
          <ChatMessages isMobileView={isMobileView} />
        ) : (
          <ConfigurePanel />
        )}
      </div>
    </div>
  )
}

import styles from './CompactNodePanel.module.css'
import {sendEvent} from '@github-ui/hydro-analytics'
import {ExecuteButton} from '../../controls/ExecuteButton'
import {InputSection} from '../InputSection'
import {useNodeEdit} from '../../../hooks/use-node-edit'
import {useNodeValue, useNodeRunning} from '../../../state/lenses'
import {NodeContextMenu} from '../../controls/NodeContextMenu'
import {NodeType, NodeLabel} from '../NodeType'
import {Icon} from '@github-ui/pacer/Icon'
import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {OutputSection} from '../OutputSection'
import {nodeHandlerRegistry} from '../../../service/node-handler-registry'

function EmptyNodePanel() {
  const {streamingMessage, isWaitingOnCopilot} = useChatState()
  const isStreaming = streamingMessage || isWaitingOnCopilot

  return (
    <div className={styles.panelEmptyState}>
      <Icon icon="node" size={32} />
      {isStreaming ? (
        <span>Select a node in the loop once creation has completed.</span>
      ) : (
        <span>Select a node in the loop to view and edit.</span>
      )}
    </div>
  )
}

function ActiveNodePanel({nodeId, pipelineId}: {nodeId: string; pipelineId: string}) {
  const {node, onUpdate, runPipelineFromNode, onStop} = useNodeEdit({nodeId, pipelineId})
  const nodeValue = useNodeValue(nodeId)
  const isRunning = useNodeRunning(nodeId)

  if (!node) return null

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <div className={styles.nodeDetails}>
          <div className={styles.nodeTitleContainer}>
            <NodeType type={node.type} node={node} />
            <span className={styles.nodeTitleText}>{node.title}</span>
            <NodeLabel type={node.type} node={node} />
          </div>
          <span className={styles.descriptionText}>{node.description}</span>
        </div>
        <div className={styles.nodeActions}>
          {nodeHandlerRegistry.isExecutable(node.type) && (
            <ExecuteButton
              onClick={() => {
                runPipelineFromNode()
                sendEvent('node_action.select', {target: 'PANEL_NODE_RUN', mode: 'loops'})
              }}
              onStop={() => {
                onStop()
                sendEvent('node_action.select', {target: 'PANEL_NODE_STOP', mode: 'loops'})
              }}
              isLoading={isRunning}
              value={nodeValue}
              variant="default"
              iconOnly
            />
          )}
          <NodeContextMenu nodeId={nodeId} />
        </div>
      </div>
      <div className={styles.content}>
        <div className={styles.input}>
          <InputSection
            nodeId={nodeId}
            pipelineId={pipelineId}
            isContentVisible
            isCollapsed={false}
            isLoading={isRunning}
            onUpdate={onUpdate}
          />
        </div>

        <div className={styles.output}>
          {nodeHandlerRegistry.isExecutable(node.type) && (
            <OutputSection
              isRunning={isRunning}
              node={node}
              nodeId={nodeId}
              onRun={runPipelineFromNode}
              onStop={onStop}
            />
          )}
        </div>
      </div>
    </div>
  )
}

interface CompactNodePanelProps {
  nodeId?: string | null
  pipelineId?: string | null
}

export function CompactNodePanel({nodeId, pipelineId}: CompactNodePanelProps) {
  return nodeId && pipelineId ? <ActiveNodePanel nodeId={nodeId} pipelineId={pipelineId} /> : <EmptyNodePanel />
}

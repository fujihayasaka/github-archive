import {useState} from 'react'
import {Button} from '@primer/react'
import {ChevronDownIcon, ChevronRightIcon} from '@primer/octicons-react'
import {NodeOutput} from './NodeOutput'
import {NodeError} from './NodeError'
import type {Node} from '../../types/app'
import styles from './OutputSection.module.css'
import {useLoopIsRunning, useNodeError, useNodeValue} from '../../state/lenses'
import {useNodeValidationErrors} from '../../hooks/use-validation-errors'
import {useAppContext} from '../../contexts/AppContextProvider'
import {sendEvent} from '@github-ui/hydro-analytics'
import {ExecuteButton} from '../controls/ExecuteButton'
import {NodeRunning} from './NodeRunning'

interface OutputSectionProps {
  isRunning: boolean
  node: Node
  nodeId: string
  onRun: () => void
  onStop: () => void
}

export function OutputSection({isRunning, node, nodeId, onRun, onStop}: OutputSectionProps) {
  const nodeError = useNodeError(nodeId)
  const nodeValue = useNodeValue(nodeId)
  const validationErrors = useNodeValidationErrors(nodeId)
  const isLoopRunning = useLoopIsRunning()
  const {sendChatMessage} = useAppContext()
  const [isExpanded, setIsExpanded] = useState(true)

  const sendFixChatMessage = () => {
    if (!validationErrors.length && !nodeError) return

    let message: string
    if (validationErrors.length) {
      const errors = validationErrors.map(error => `- ${error}`).join('\n')
      message = `The following errors were found in the Loop configuration:\n${errors}`
    } else {
      message = `The following error was found when running node ${nodeId}:\n${nodeError}`
    }

    message += `\n\nFix the Loop by updating this node or other nodes upstream in the Loop.`

    sendChatMessage(message)
    sendEvent('dotcom_chat.activate', {target: 'PANEL_NODE_FIX_ERROR', mode: 'loops'})
  }

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <Button
          leadingVisual={isExpanded ? ChevronDownIcon : ChevronRightIcon}
          aria-label={isExpanded ? 'Collapse output section' : 'Expand output section'}
          onClick={() => setIsExpanded(!isExpanded)}
          variant="invisible"
          size="small"
          className={styles.groupTitle}
        >
          Output
        </Button>
      </div>
      {isExpanded && (
        <>
          <div className={styles.output}>
            {isLoopRunning && !nodeValue ? (
              <NodeRunning isRunning={isRunning} />
            ) : validationErrors.length > 0 ? (
              <NodeError
                errors={validationErrors}
                onFixErrorClick={sendFixChatMessage}
                title="Oops, this node is configured incorrectly"
              />
            ) : nodeError ? (
              <NodeError errors={[nodeError]} onFixErrorClick={sendFixChatMessage} />
            ) : nodeValue ? (
              <NodeOutput isRunning={isRunning} node={node} nodeValue={nodeValue} />
            ) : (
              <div className={styles.emptyState}>
                <ExecuteButton
                  onClick={() => {
                    onRun()
                    sendEvent('node_action.select', {target: 'PANEL_NODE_EMPTY_STATE_RUN', mode: 'loops'})
                  }}
                  onStop={() => {
                    onStop()
                    sendEvent('node_action.select', {target: 'PANEL_NODE_EMPTY_STATE_STOP', mode: 'loops'})
                  }}
                  isLoading={isRunning}
                  value={nodeValue}
                  variant="default"
                />
                <p className={styles.emptyStateText}>
                  No output yet.
                  <br /> Run this node to generate output.
                </p>
              </div>
            )}
          </div>
        </>
      )}
    </div>
  )
}

import {usePipesStateLens} from '../../../contexts/PipesStateProvider'
import styles from './CompactNode.module.css'
import {
  nodeDefinition,
  useNode,
  useNodeIndicatorStatus,
  useNodeRunning,
  useNodeType,
  type Status,
} from '../../../state/lenses'
import {NodeType as NodeTypeComponent} from '../NodeType'
import type {NodeType as NodeTypeProps} from '../../../types/app'
import {AlertIcon} from '../../CustomIcon'
import {clsx} from 'clsx'
import {Spinner, useTheme} from '@primer/react'
import {useLoopLens} from '../../../hooks/use-loop-lens'
import {useHasValidationErrors} from '../../../hooks/use-validation-errors'

interface NodeProps {
  nodeId: string
  pipelineId: string
  className?: string
  hasPredecessors?: boolean
  hasSuccessors?: boolean
  title?: string
  type?: NodeTypeProps
}

interface IndicatorProps {
  status: Status
}

const InputIndicator = ({status}: IndicatorProps) => (
  <div
    className={clsx(
      styles.indicatorDot,
      styles.topDot,
      status === 'COMPLETED' && styles.completed,
      status === 'ERROR' && styles.error,
    )}
  />
)

const OutputIndicator = ({status}: IndicatorProps) => (
  <div
    className={clsx(
      styles.indicatorDot,
      styles.bottomDot,
      status === 'COMPLETED' && styles.completed,
      status === 'ERROR' && styles.error,
    )}
  >
    <div className={styles.indicatorShadowWrapper}>
      <div className={styles.indicatorShadow} />
    </div>
  </div>
)

export function CompactNode({nodeId, pipelineId, className, hasPredecessors, hasSuccessors, title, type}: NodeProps) {
  const node = useNode(nodeId)
  const isRunning = useNodeRunning(nodeId)
  const theme = useTheme()
  const nodeTitle = useLoopLens(loop => nodeDefinition(nodeId, loop)?.title)
  title = title || nodeTitle
  const nodeType = useNodeType(nodeId)
  type = type || nodeType
  const selected = usePipesStateLens(s => s.uiState.focusedNodeId === nodeId)

  const indicatorStatus: Status = useNodeIndicatorStatus(nodeId)

  return (
    <div
      id={`node-card-${pipelineId}-${nodeId}`}
      className={clsx(
        styles.compactNode,
        className,
        selected ? styles.active : null,
        theme.colorScheme?.includes('dark') || theme.colorScheme?.includes('night') ? styles.dark : '',
      )}
    >
      {hasPredecessors && <InputIndicator status={indicatorStatus} />}
      {hasSuccessors && <OutputIndicator status={indicatorStatus} />}
      {isRunning ? <Spinner size="small" /> : <NodeTypeComponent type={type} size="medium" node={node} />}
      <p className={styles.title}>{title}</p>
      <ValidationErrorsIndicator nodeId={nodeId} />
    </div>
  )
}

function ValidationErrorsIndicator({nodeId}: {nodeId: string}) {
  const hasValidationErrors = useHasValidationErrors(nodeId)

  if (!hasValidationErrors) return null

  return (
    <div className={styles.validationErrorWrapper}>
      <AlertIcon />
    </div>
  )
}

import {AlertIcon} from '@primer/octicons-react'
import {usePipesStateLens} from '../../../contexts/PipesStateProvider'
import type {Node} from '../../../types/app'
import styles from './CompactStyle.module.css'
import {nodeDefinition, useHasValidationErrors, useNodeType} from '../../../state/lenses'
import {NodeType} from '../NodeType'

interface CompactStyleProps {
  nodeId: string
  pipelineId: string
  isContentVisible?: boolean
  isLoading?: boolean
  renderedValue?: string | undefined
  processedCode?: {
    processedCode: string
    otherFiles: Record<string, string>
    dependencies: string[]
  }
  className?: string
  isUpdating?: boolean
  isOutput?: boolean
  isSelected: boolean
  onToggleExpand?: (expand: boolean) => void
  handleNodeUpdate?: () => void
  handleUpdate?: (updates: Partial<Node>) => void
  handleStop?: (e: React.MouseEvent) => void
  setIsContentVisible?: React.Dispatch<React.SetStateAction<boolean>>
}

export const CompactStyle: React.FC<CompactStyleProps> = ({
  nodeId,
  pipelineId,
  isSelected,
  className,
  // isContentVisible,
  // isLoading,
  // renderedValue,
  // processedCode,
  // isOutput,
  // isUpdating,
  // onToggleExpand,
  // handleNodeUpdate,
  // handleUpdate,
  // handleStop,
  // setIsContentVisible,
}) => {
  const title = usePipesStateLens(s => nodeDefinition(nodeId)(s)?.title)
  const type = useNodeType(nodeId)
  return (
    <div
      id={`node-card-${pipelineId}-${nodeId}`}
      className={`${styles.compactNode} ${className} ${isSelected ? styles.active : ''}`}
    >
      <NodeType type={type} size="medium" />
      <p style={{margin: '0', width: 'max-content'}}>{title}</p>
      <ValidationErrorsIndicator nodeId={nodeId} />
    </div>
  )
}

function ValidationErrorsIndicator({nodeId}: {nodeId: string}) {
  const hasValidationErrors = useHasValidationErrors(nodeId)

  if (!hasValidationErrors) return null

  return <AlertIcon className={styles.validationError} />
}

import {clsx} from 'clsx'
import {nodeHandlerRegistry} from '../../service/node-handler-registry'
import type {Node, NodeType} from '../../types/app'
import styles from './NodeType.module.css'

interface NodeTypeProps {
  node?: Node
  size?: 'small' | 'medium' | 'large'
  type: NodeType
}

export function NodeType({node, size = 'medium', type}: NodeTypeProps) {
  const config = nodeHandlerRegistry.getMetadata(type)
  const Icon = config?.icon(node)
  const iconSize = size === 'small' ? 10 : size === 'large' ? 24 : 16
  const containerWidth = iconSize

  if (!Icon) return null

  return (
    <div
      className={styles.iconContainer}
      style={{
        height: containerWidth,
        width: containerWidth,
      }}
    >
      <Icon size={iconSize} className={styles.icon} />
    </div>
  )
}

interface NodeLabelProps {
  className?: string
  node?: Node
  type: NodeType
}

export function NodeLabel({node, type}: NodeLabelProps) {
  const config = nodeHandlerRegistry.getMetadata(type)
  const label = config?.label(node)

  return <div className={clsx(styles.labelContainer, styles.icon)}>{label}</div>
}

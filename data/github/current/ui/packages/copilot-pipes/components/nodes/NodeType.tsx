import {clsx} from 'clsx'
import {pipeTypesInfo} from '../../types/pipe-types'
import type {NodeType} from '../../types/app'
import styles from './NodeType.module.css'

interface NodeTypeProps {
  type: NodeType
  size?: 'small' | 'medium' | 'large'
  className?: string
}

export function NodeType({type, className, size = 'medium'}: NodeTypeProps) {
  const config = pipeTypesInfo[type]
  const color = config?.color
  const Icon = config?.icon
  const iconSize = size === 'small' ? 10 : size === 'large' ? 24 : 16
  const containerWidth = iconSize

  return (
    <div
      className={clsx(styles.typePicker, className)}
      style={{
        height: containerWidth,
        width: containerWidth,
      }}
    >
      <Icon size={iconSize} className={color} />
    </div>
  )
}

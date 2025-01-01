import type {MouseEvent} from 'react'

import type {Node} from '../../../types/app'
import styles from './PillBoxNodeHeader.module.css'
import {clsx} from 'clsx'
import {ExecuteButton} from '../../controls/ExecuteButton'
import {EditableText} from '../../controls/EditableText'
import {NodeType} from '../NodeType'
import {useNodeValue, useNodeRunning, useNode} from '../../../state/lenses'

export function PillBoxNodeHeader({
  isCollapsed,
  nodeId,
  onNodeUpdate,
  onStop,
  onToggleExpand,
  onUpdate,
}: {
  isCollapsed: boolean
  nodeId: string
  onNodeUpdate: () => void
  onStop: (e: MouseEvent) => void
  onToggleExpand: (isCollapsed: boolean) => void
  onUpdate: (newValues: Partial<Node>) => void
}) {
  const value = useNodeValue(nodeId)
  const isRunning = useNodeRunning(nodeId)
  const node = useNode(nodeId)

  if (!node) return null
  return (
    // eslint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions
    <div className={styles.container} onClick={() => onToggleExpand(!isCollapsed)}>
      <div className={clsx(styles.mainContent, isRunning && styles.isLoading)}>
        <NodeType type={node.type} />

        <div className={clsx(styles.titleAndDescriptionContainer, isCollapsed && styles.collapsed)}>
          <div className={styles.titleContainer}>
            <EditableText
              className={styles.title}
              value={node.title}
              onChange={(newValue: string) => {
                onUpdate({title: newValue})
              }}
              onClick={e => e.stopPropagation()}
              isEditable={!isCollapsed}
            />
          </div>
          <div className={styles.descriptionContainer}>
            <EditableText
              className={styles.description}
              value={node.description}
              onChange={(newValue: string) => {
                onUpdate({description: newValue})
              }}
              onClick={e => e.stopPropagation()}
              isEditable={!isCollapsed}
            />
          </div>
        </div>

        {['prompt', 'code', 'pdf', 'pipeline', 'github-graphql'].includes(node.type) && (
          <ExecuteButton
            onClick={e => {
              e.stopPropagation()
              onNodeUpdate()
            }}
            onStop={e => {
              e.stopPropagation()
              onStop(e)
            }}
            isLoading={isRunning}
            type={node.type}
            value={value}
            className={styles.executeButton}
          />
        )}
      </div>
    </div>
  )
}

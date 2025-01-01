import type {Node} from '../../../types/app'
import type React from 'react'
import styles from './PillBoxNode.module.css'
import {clsx} from 'clsx'
import {PillBoxNodeHeader} from './PillBoxNodeHeader'
import {ExpandedPillBoxContent} from './ExpandedPillBoxContent'
import {CollapsedPillBoxContent} from './CollapsedPillBoxContent'
import {NodeConnection} from '../NodeConnection'
import {useRef} from 'react'
import {useNodeInputIds, useNodeType} from '../../../state/lenses'

interface PillBoxNodeProps {
  nodeId: string
  pipelineId: string
  isCollapsed: boolean
  isContentVisible: boolean
  className?: string
  isOutput: boolean
  onNodeUpdate: () => void
  onStop: (e: React.MouseEvent) => void
  onToggleExpand: (expand: boolean) => void
  onToggleContent: () => void
  onUpdate: (updates: Partial<Node>) => void
}

export const PillBoxNode: React.FC<PillBoxNodeProps> = ({
  nodeId,
  pipelineId,
  isCollapsed,
  isContentVisible,
  className,
  isOutput,
  onToggleExpand,
  onNodeUpdate,
  onUpdate,
  onStop,
  onToggleContent,
}) => {
  const container = useRef<HTMLDivElement>(null)
  const type = useNodeType(nodeId)
  const inputs = useNodeInputIds(nodeId)
  return (
    <>
      <div
        // initial={{opacity: 0, y: 10}}
        // animate={{opacity: 1, y: 0}}
        // exit={{opacity: 0, y: 10}}
        // transition={{duration: 0.2}}
        id={`node-card-${pipelineId}-${nodeId}`}
        className={clsx(
          'node-component',
          styles.container,
          className,
          isCollapsed ? '' : type !== 'text' ? styles.node : styles.textNode,
        )}
        ref={container}
      >
        <div className={styles.mainContent}>
          <span className={styles.nodeIdBox}>{nodeId}</span>
          <div className={clsx('node-component', styles.headerContainer)}>
            <PillBoxNodeHeader
              isCollapsed={isCollapsed}
              nodeId={nodeId}
              onNodeUpdate={onNodeUpdate}
              onStop={onStop}
              onToggleExpand={onToggleExpand}
              onUpdate={onUpdate}
            />
            <div className={clsx(styles.nodeMarker, `node-component-${pipelineId}-${nodeId}`)} />
          </div>
          {!isCollapsed && (
            <ExpandedPillBoxContent
              nodeId={nodeId}
              pipelineId={pipelineId}
              isOutput={isOutput}
              isCollapsed={isCollapsed}
              isContentVisible={isContentVisible}
              onNodeUpdate={onNodeUpdate}
              onStop={onStop}
              onToggleContent={onToggleContent}
              onUpdate={onUpdate}
            />
          )}
        </div>
        {isCollapsed && <CollapsedPillBoxContent nodeId={nodeId} />}
      </div>

      <div className={styles.nodeConnection}>
        {inputs.map((input: string) => {
          return (
            <NodeConnection
              key={input}
              containerRef={container}
              from={`node-component-${pipelineId}-${input}`}
              to={`node-component-${pipelineId}-${nodeId}`}
              isSplit={input.includes('|map')}
            />
          )
        })}
      </div>
    </>
  )
}

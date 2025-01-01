import {useState} from 'react'
import type {Pipeline} from '../../types/app'
import styles from './LoopBlock.module.css'
import {Button} from '@primer/react'
import {ChevronDownIcon, ChevronRightIcon, CheckCircleFillIcon} from '@primer/octicons-react'
import {clsx} from 'clsx'

export interface LoopBlockContentProps {
  loop: Pipeline | null
  headerButton?: React.ReactNode
  isStreaming?: boolean
}

export function LoopBlockContent({loop, headerButton, isStreaming}: LoopBlockContentProps) {
  const [isExpanded, setIsExpanded] = useState(true)

  if (!loop) return null

  const toggleExpand = () => setIsExpanded(!isExpanded)

  return (
    <div className={clsx(styles.container, isStreaming && styles.streaming)}>
      <div className={clsx(styles.header, !isExpanded && styles.headerCollapsed)}>
        <Button
          variant="invisible"
          onClick={toggleExpand}
          className={styles.expandButton}
          leadingVisual={isExpanded ? <ChevronDownIcon size={16} /> : <ChevronRightIcon size={16} />}
        >
          <span>{loop.title}</span>
        </Button>
        {headerButton}
      </div>
      {isExpanded && (
        <div className={styles.content}>
          {loop.nodes.map((node, index) => {
            // only treat the last node as streaming
            const isNodeStreaming = isStreaming && index === loop.nodes.length - 1

            return (
              <div key={node.id} className={styles.node}>
                <div className={styles.iconContainer}>
                  <CheckCircleFillIcon size={16} className={styles.checkIcon} />
                </div>
                {isNodeStreaming && !node.title ? null : <span className={styles.nodeTitle}>{node.title}</span>}
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}

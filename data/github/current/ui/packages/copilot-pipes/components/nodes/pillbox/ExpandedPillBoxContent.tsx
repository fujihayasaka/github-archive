import {MarkdownRenderer} from '@github-ui/copilot-markdown'
import {AlertIcon} from '@primer/octicons-react'
import {SkeletonText} from '@primer/react/experimental'
import type {MouseEvent} from 'react'
import type {Node} from '../../../types/app'
import {clsx} from 'clsx'
import styles from './ExpandedPillBoxContent.module.css'
import {NodeContent} from '../NodeContent'
import {ExecuteButton} from '../../controls/ExecuteButton'
import {useNodeError, useNodeValue, useNodeRunning, useNodeType} from '../../../state/lenses'

export function ExpandedPillBoxContent({
  isCollapsed,
  isContentVisible,
  isOutput,
  nodeId,
  onNodeUpdate,
  onStop,
  onToggleContent,
  onUpdate,
  pipelineId,
}: {
  isCollapsed: boolean
  isContentVisible: boolean
  isOutput: boolean
  nodeId: string
  onNodeUpdate: () => void
  onStop: (e: MouseEvent) => void
  onToggleContent: () => void
  onUpdate: (updates: Partial<Node>) => void
  pipelineId: string
}) {
  const nodeValue = useNodeValue(nodeId)
  const nodeError = useNodeError(nodeId)
  const isRunning = useNodeRunning(nodeId)
  const nodeType = useNodeType(nodeId)
  return (
    <div
      // initial={{height: 0}}
      // animate={{height: 'auto'}}
      // exit={{height: 0}}
      // transition={{duration: 0.2}}
      className={clsx(styles.container, 'group/card')}
    >
      <div className={styles.innerContainer}>
        <div className={styles.nodeContent}>
          <NodeContent
            nodeId={nodeId}
            pipelineId={pipelineId}
            isContentVisible={isContentVisible}
            isCollapsed={isCollapsed}
            isLoading={isRunning}
            onUpdate={onUpdate}
            onToggleContent={onToggleContent}
          />
        </div>

        {['prompt', 'code', 'pdf', 'pipeline', 'github-graphql'].includes(nodeType) && (
          <>
            <div className={styles.divider} />

            <div className={styles.outputContainer}>
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
                type={nodeType}
                value={nodeValue}
                className={styles.executeButton}
              />
              {isRunning && !nodeValue ? (
                <div className={styles.loading}>
                  <SkeletonText lines={3} />
                </div>
              ) : nodeError ? (
                <div className={styles.errorContainer}>
                  <div className={styles.errorNotice}>
                    <AlertIcon className={styles.errorIcon} />
                    Oops, we hit an error
                  </div>
                  <p className={styles.errorText}>{nodeError}</p>
                </div>
              ) : nodeValue ? (
                <div className={clsx(styles.nodeValue, isOutput && styles.output)}>
                  {nodeType === 'github-graphql' ? (
                    <pre
                      style={{
                        maxHeight: 300,
                        overflow: 'auto',
                        paddingTop: 16,
                        paddingBottom: 16,
                        paddingLeft: 32,
                        paddingRight: 32,
                      }}
                    >
                      {nodeValue.toString()}
                    </pre>
                  ) : (
                    <div style={{paddingTop: 16, paddingBottom: 16, paddingLeft: 32, paddingRight: 32}}>
                      <MarkdownRenderer markdown={nodeValue.toString() ?? ''} />
                    </div>
                  )}
                </div>
              ) : null}
            </div>
          </>
        )}
      </div>
    </div>
  )
}

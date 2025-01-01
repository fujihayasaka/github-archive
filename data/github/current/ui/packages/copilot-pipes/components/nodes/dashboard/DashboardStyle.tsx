import {Text} from '@primer/react'
import {clsx} from 'clsx'
import type {Node, NodeValue} from '../../../types/app'
import styles from './DashboardStyle.module.css'
import {ExecuteButton} from '../../controls/ExecuteButton'
import {NodeContent} from '../NodeContent'
import {MarkdownRenderer} from '@github-ui/copilot-markdown'
import {AlertIcon, CopyIcon} from '@primer/octicons-react'
import {SkeletonText} from '@primer/react/experimental'
import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {isGitHubGraphQLNode} from '../../../utils/node-assertions'
import {useNode, useNodeError, useNodeRunning, useNodeValue, useValidationErrors} from '../../../state/lenses'

interface DashboardStyleProps {
  nodeId: string
  pipelineId: string
  isContentVisible: boolean
  renderedValue?: NodeValue | undefined
  processedCode?: {
    processedCode: string
    otherFiles: Record<string, string>
    dependencies: string[]
  }
  className?: string
  isUpdating?: boolean
  isOutput: boolean
  onStop: (e: React.MouseEvent) => void
  onUpdate: (updates: Partial<Node>) => void
  onNodeUpdate: () => void
  onToggleContent: () => void
  onToggleExpand?: (expand: boolean) => void
  setIsContentVisible?: React.Dispatch<React.SetStateAction<boolean>>
}

export const DashboardStyle: React.FC<DashboardStyleProps> = ({
  nodeId,
  pipelineId,
  // className,
  // isContentVisible,
  onStop,
  onUpdate,
  onNodeUpdate,
  onToggleContent,
  // renderedValue,
  // processedCode,
  isOutput,
  // isUpdating,
  // onToggleExpand,
  // handleNodeUpdate,
  // handleUpdate,
  // handleStop,
  // setIsContentVisible,
}) => {
  const nodeError = useNodeError(nodeId)
  const nodeValue = useNodeValue(nodeId)
  const isRunning = useNodeRunning(nodeId)
  const validationErrors = useValidationErrors(nodeId)
  const renderedValue = useNodeValue(nodeId)
  const node = useNode(nodeId)

  if (!node) return null
  return (
    <div id={`node-card-${pipelineId}-${nodeId}`} className={styles.container}>
      <div className={styles.header}>
        <div className={styles.title}>
          <Text size="medium" weight="semibold" className="fgColor-default">
            {node.title}
          </Text>
          <Text size="medium" weight="normal" className="fgColor-muted">
            {node.description}
          </Text>
        </div>
        <div className="trigger-btn">
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
              value={nodeValue}
              variant="default"
            />
          )}
        </div>
      </div>
      <div className={styles.content}>
        <NodeContent
          nodeId={nodeId}
          pipelineId={pipelineId}
          isContentVisible
          isCollapsed={false}
          isLoading={isRunning}
          onUpdate={onUpdate}
          onToggleContent={onToggleContent}
        />

        {['prompt', 'code', 'pdf', 'pipeline', 'github-graphql'].includes(node.type) && (
          <>
            <div className={styles.divider} />

            <div className={styles.outputContainer}>
              {isRunning && !nodeValue ? (
                <div className={styles.loading}>
                  <SkeletonText lines={3} />
                </div>
              ) : validationErrors.length > 0 ? (
                <div className={styles.errorContainer}>
                  {validationErrors.map(validationError => (
                    <div key={validationError}>
                      <div className={styles.errorNotice}>
                        <AlertIcon className={styles.errorIcon} />
                        Oops, this node is configured incorrectly
                      </div>
                      <p className={styles.errorText}>{validationError}</p>
                    </div>
                  ))}
                </div>
              ) : nodeError ? (
                <div className={styles.errorContainer}>
                  <div className={styles.errorNotice}>
                    <AlertIcon className={styles.errorIcon} />
                  </div>
                  <p className={styles.errorText}>{nodeError}</p>
                </div>
              ) : renderedValue ? (
                <div className={clsx(styles.nodeValue, isOutput && styles.output)}>
                  {isGitHubGraphQLNode(node) ? (
                    <pre
                      style={{
                        maxHeight: 300,
                        overflow: 'auto',
                      }}
                    >
                      {renderedValue.toString()}
                    </pre>
                  ) : (
                    <div className={styles.markdownContainer}>
                      <div className={styles.markdownHeader}>
                        <Text size="small" weight="semibold">
                          Output
                        </Text>
                        <CopyToClipboardButton
                          icon={CopyIcon}
                          variant="invisible"
                          ariaLabel="Copy output"
                          textToCopy={renderedValue ? renderedValue.toString() : ''}
                        />
                      </div>
                      <div className={styles.markdownContentWrapper}>
                        <MarkdownRenderer markdown={renderedValue.toString() ?? ''} />
                      </div>
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

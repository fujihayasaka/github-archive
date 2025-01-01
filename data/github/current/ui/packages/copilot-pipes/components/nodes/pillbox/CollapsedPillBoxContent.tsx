import {MarkdownRenderer} from '@github-ui/copilot-markdown'
import {AlertIcon} from '@primer/octicons-react'
import styles from './CollapsedPillBoxContent.module.css'
import {useNodeError, useNodeType, useNodeValue} from '../../../state/lenses'

export function CollapsedPillBoxContent({nodeId}: {nodeId: string}) {
  const nodeError = useNodeError(nodeId)
  const renderedValue = useNodeValue(nodeId)
  const nodeType = useNodeType(nodeId)
  return (
    <div className={styles.container}>
      {nodeError ? (
        <div className={styles.errorContainer}>
          <div className={styles.iconContainer}>
            <AlertIcon />
          </div>
          <p className={styles.errorText}>{nodeError}</p>
        </div>
      ) : (
        // <NodeValueSummaryView value={renderedValue || ''} type={node.type} />
        !!renderedValue &&
        nodeType !== 'github-graphql' && (
          <div style={{paddingTop: 16, paddingBottom: 16, paddingLeft: 32, paddingRight: 32}}>
            <MarkdownRenderer markdown={renderedValue.toString() ?? ''} />
          </div>
        )
      )}
    </div>
  )
}

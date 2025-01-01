import {MarkdownRenderer} from '@github-ui/copilot-markdown'
import {CopyIcon} from '@primer/octicons-react'
import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {isGitHubGraphQLNode} from '../../utils/node-assertions'
import {nodeHandlerRegistry} from '../../service/node-handler-registry'
import styles from './NodeOutput.module.css'
import type {Node, NodeValue} from '../../types/app'
import codeBlocksForLoopExtension from '../../markdown-extensions/code-blocks/CodeBlocks'
import {stringifyNodeValue} from '../../utils/utils'
import {useAppContext} from '../../contexts/AppContextProvider'
import mermaidExtension from '@github-ui/copilot-markdown/extensions/Mermaid'
import {useMemo} from 'react'

interface NodeOutputProps {
  isRunning: boolean
  node: Node
  nodeValue: NodeValue
}

export function NodeOutput({isRunning, node, nodeValue}: NodeOutputProps) {
  const {previewUrl} = useAppContext()

  const extensions = useMemo(() => {
    const extensionsList = [codeBlocksForLoopExtension()]
    if (previewUrl) {
      extensionsList.push(mermaidExtension({viewscreenHost: previewUrl}))
    }

    return extensionsList
  }, [previewUrl])

  const outputLabel = nodeHandlerRegistry.getMetadata(node.type)?.outputLabel ?? 'Markdown'
  const valueString = stringifyNodeValue(nodeValue)

  return (
    <>
      <div className={styles.outputHeader}>
        <div className={styles.outputType}>{outputLabel}</div>
        <CopyToClipboardButton icon={CopyIcon} variant="invisible" ariaLabel="Copy output" textToCopy={valueString} />
      </div>
      <div className={styles.nodeValue}>
        {isGitHubGraphQLNode(node) ? (
          <pre className={styles.jsonOutput}>{valueString}</pre>
        ) : (
          <MarkdownRenderer
            extensions={extensions}
            className={styles.markdownOutput}
            isStreaming={isRunning}
            markdown={valueString}
          />
        )}
      </div>
    </>
  )
}

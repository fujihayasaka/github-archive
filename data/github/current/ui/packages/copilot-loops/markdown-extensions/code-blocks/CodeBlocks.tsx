import type {CopilotMarkdownExtension, ReactComponentsExtension} from '@github-ui/copilot-markdown/extension'
import {dataAttrToPropName, parseJsonAttribute} from '@github-ui/copilot-markdown/utils'
import {CodeBlocksForLoop, type CodeBlocksForLoopProps} from './CodeBlocksForLoop'

import {visit} from 'unist-util-visit'

const codeblockAttribute = 'data-codeblock-for-loop-props'
const codeblockProperty = dataAttrToPropName(codeblockAttribute)

const reactComponents: ReactComponentsExtension = {
  code: (props, fallthrough) => {
    const codeblockForLoopProps = parseJsonAttribute<CodeBlocksForLoopProps>(props, codeblockAttribute)
    if (!codeblockForLoopProps) return fallthrough

    return <CodeBlocksForLoop {...codeblockForLoopProps}>{props.children}</CodeBlocksForLoop>
  },
}

export default function codeBlocksForLoopExtension(): CopilotMarkdownExtension {
  return {
    transformMarkdown: tree =>
      visit(tree, 'code', node => {
        node.data = {
          ...node.data,
          hName: 'code',
          hProperties: {
            [codeblockProperty]: JSON.stringify({
              language: node.lang ?? '',
              code: node.value,
              // Every component will receive a node. This is the original Element from hast element being turned into a React element.
              // see https://github.com/remarkjs/react-markdown/tree/main?tab=readme-ov-file#appendix-b-components
              startOffset: node.position?.start.offset ?? -1,
              endOffset: node.position?.end.offset ?? -1,
            } satisfies CodeBlocksForLoopProps),
          },
        }
      }),
    transformHtml: tree =>
      // Code nodes render as two nested elements (pre > code) by default, so we transform the html to remove the outer element
      visit(tree, 'element', (node, i, parent) => {
        const child = node.children?.[0]
        if (
          parent &&
          i !== undefined &&
          node.tagName === 'pre' &&
          node.children?.length === 1 &&
          child?.type === 'element' &&
          child.tagName === 'code' &&
          codeblockProperty in child.properties
        )
          parent.children.splice(i, 1, child)
      }),
    reactComponents,
  }
}

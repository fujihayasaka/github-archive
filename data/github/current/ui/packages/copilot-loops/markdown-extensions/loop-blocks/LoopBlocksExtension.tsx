import type {CopilotMarkdownExtension, ReactComponentsExtension} from '@github-ui/copilot-markdown/extension'
import {dataAttrToPropName, parseJsonAttribute} from '@github-ui/copilot-markdown/utils'
import {visit} from 'unist-util-visit'

import {LoopBlock, type LoopBlockProps} from './LoopBlock'

export const loopBlockAttribute = 'data-loop-block'
const loopBlockProperty = dataAttrToPropName(loopBlockAttribute)

const reactComponents: ReactComponentsExtension = {
  div: (props, fallthrough) => {
    const loopBlockProps = parseJsonAttribute<LoopBlockProps>(props, loopBlockAttribute)
    if (!loopBlockProps) return fallthrough

    return <LoopBlock {...loopBlockProps} />
  },
}

export default function loopBlocksExtension(): CopilotMarkdownExtension {
  return {
    transformMarkdown: tree =>
      // Code nodes render as two nested elements (pre > code) by default, and setting the hName only overrides the
      // inner element. So we have to transform the html by removing the outer element
      visit(tree, 'code', node => {
        if (node.lang !== 'loop') return

        node.data = {
          hName: 'div',
          hProperties: {
            [loopBlockProperty]: JSON.stringify({
              isStreaming: node.isStreaming ?? false,
            } satisfies LoopBlockProps),
          },
          hChildren: [],
        }
      }),
    transformHtml: tree =>
      visit(tree, 'element', (node, i, parent) => {
        const child = node.children?.[0]
        if (
          parent &&
          i !== undefined &&
          node.tagName === 'pre' &&
          node.children?.length === 1 &&
          child?.type === 'element' &&
          loopBlockProperty in child.properties
        )
          parent.children.splice(i, 1, child)
      }),
    reactComponents,
  }
}

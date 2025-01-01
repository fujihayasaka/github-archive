import type {CopilotMarkdownExtension, ReactComponentsExtension} from '@github-ui/copilot-markdown/extension'
import {dataAttrToPropName, parseJsonAttribute} from '@github-ui/copilot-markdown/utils'
import {ToolCodeBlock, type ToolCodeBlockProps} from './ToolCodeBlock'

import {visit} from 'unist-util-visit'

const codeblockAttribute = 'data-tool-codeblock-props'
const codeblockProperty = dataAttrToPropName(codeblockAttribute)

const reactComponents: ReactComponentsExtension = {
  code: (props, fallthrough) => {
    const codeblockProps = parseJsonAttribute<ToolCodeBlockProps>(props, codeblockAttribute)
    if (!codeblockProps) return fallthrough

    return <ToolCodeBlock {...codeblockProps}>{props.children}</ToolCodeBlock>
  },
}

export type ToolCodeBlockExtensionArgs = {
  characterCount?: number
  bashLoading?: boolean
}

export default function toolCodeBlockExtension(args: ToolCodeBlockExtensionArgs = {}): CopilotMarkdownExtension {
  const {characterCount, bashLoading} = args
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
              characterCount: characterCount ?? 0,
              bashLoading: !!bashLoading,
            } satisfies ToolCodeBlockProps),
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

// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import type {CopilotMarkdownExtension, ReactComponentsExtension} from '../../extension'
import {dataAttrToPropName, parseJsonAttribute} from '../../utils'
import {CodeBlock, type CodeBlockProps} from './CodeBlock'

import {visit} from 'unist-util-visit'

const codeblockAttribute = 'data-codeblock-props'
const codeblockProperty = dataAttrToPropName(codeblockAttribute)

const reactComponents: ReactComponentsExtension = {
  code: (props, fallthrough) => {
    const codeblockProps = parseJsonAttribute<CodeBlockProps>(props, codeblockAttribute)
    if (!codeblockProps) return fallthrough

    return <CodeBlock {...codeblockProps}>{props.children}</CodeBlock>
  },
}

export default function codeBlocksExtension(): CopilotMarkdownExtension {
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
            } satisfies CodeBlockProps),
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

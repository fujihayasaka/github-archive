// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import type {CopilotMarkdownExtension, ReactComponentsExtension} from '@github-ui/copilot-markdown/extension'
import {dataAttrToPropName, parseJsonAttribute} from '@github-ui/copilot-markdown/utils'
import {visit} from 'unist-util-visit'

import {stripQuotes, typeRawRegex} from '../../utils/code-block-utils'
import {ListBlock, type ListBlockProps} from './IssueListBlock'

export const listBlockAttribute = 'data-issues-list-block'
const listBlockProperty = dataAttrToPropName(listBlockAttribute)

const reactComponents: ReactComponentsExtension = {
  div: (props, fallthrough) => {
    const listBlockProps = parseJsonAttribute<ListBlockProps>(props, listBlockAttribute)
    if (!listBlockProps) return fallthrough

    return <ListBlock {...listBlockProps} />
  },
}

export default function listExtension(): CopilotMarkdownExtension {
  return {
    transformMarkdown: tree =>
      // Code nodes render as two nested elements (pre > code) by default, and setting the hName only overrides the
      // inner element. So we have to transform the html by removing the outer element
      // TODO: Reduce duplication with file blocks logic
      visit(tree, 'code', node => {
        if (node.lang !== 'list') return

        const type = stripQuotes(typeRawRegex.exec(node.meta ?? '')?.groups?.type ?? '')
        if (type !== 'issue' && type !== 'pr') return

        node.data = {
          hName: 'div',
          hProperties: {
            [listBlockProperty]: JSON.stringify({
              data: node.value,
              type,
              isStreaming: node.isStreaming ?? false,
            } satisfies ListBlockProps),
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
          listBlockProperty in child.properties
        )
          parent.children.splice(i, 1, child)
      }),
    reactComponents,
  }
}

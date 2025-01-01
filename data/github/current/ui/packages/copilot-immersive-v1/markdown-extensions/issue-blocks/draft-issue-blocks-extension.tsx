// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import type {CopilotMarkdownExtension, ReactComponentsExtension} from '@github-ui/copilot-markdown/extension'
import {dataAttrToPropName, parseJsonAttribute} from '@github-ui/copilot-markdown/utils'
import {visit} from 'unist-util-visit'

import {stripQuotes, typeRawRegex} from '../../utils/code-block-utils'
import {DraftIssueBlock, draftIssueBlockAttribute, type DraftIssueBlockProps} from './DraftIssueBlock'

const draftIssueBlockProperty = dataAttrToPropName(draftIssueBlockAttribute)

const reactComponents: ReactComponentsExtension = {
  div: (props, fallthrough) => {
    const draftIssueProps = parseJsonAttribute<DraftIssueBlockProps>(props, draftIssueBlockAttribute)
    if (!draftIssueProps) return fallthrough

    return <DraftIssueBlock {...draftIssueProps} />
  },
}

export default function draftIssueExtension(): CopilotMarkdownExtension {
  return {
    transformMarkdown: tree =>
      visit(tree, 'code', node => {
        if (node.lang !== 'yaml') return

        const type = stripQuotes(typeRawRegex.exec(node.meta ?? '')?.groups?.type ?? '')
        if (type !== 'draft-issue') return

        node.data = {
          hName: 'div',
          hProperties: {
            [draftIssueBlockProperty]: JSON.stringify({
              yaml: node.value,
              isStreaming: node.isStreaming ?? false,
            } satisfies DraftIssueBlockProps),
          },
          hChildren: [],
        }
      }),
    transformHtml: tree =>
      // Code nodes render as two nested elements (pre > code) by default, and setting the hName only overrides the
      // inner element. So we have to transform the html by removing the outer element
      // TODO: Reduce duplication with file blocks logic
      visit(tree, 'element', (node, i, parent) => {
        const child = node.children?.[0]
        if (
          parent &&
          i != null &&
          node.tagName === 'pre' &&
          node.children?.length === 1 &&
          child?.type === 'element' &&
          draftIssueBlockProperty in child.properties
        )
          parent.children.splice(i, 1, child)
      }),
    reactComponents,
  }
}

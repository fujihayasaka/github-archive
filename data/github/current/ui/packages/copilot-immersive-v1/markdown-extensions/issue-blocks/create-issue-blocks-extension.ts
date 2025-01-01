import type {CopilotMarkdownExtension, ReactComponentsExtension} from '@github-ui/copilot-markdown/extension'
import {dataAttrToPropName} from '@github-ui/copilot-markdown/utils'
import {createElement} from 'react'
import {visit} from 'unist-util-visit'

import {stripQuotes, typeRawRegex} from '../../utils/code-block-utils'
import {CreateIssueBlock, createIssueBlockAttribute} from './CreateIssueBlock'

const createIssueBlockProperty = dataAttrToPropName(createIssueBlockAttribute)

const reactComponents: ReactComponentsExtension = {
  div: (props, fallthrough) =>
    createIssueBlockAttribute in props && typeof props[createIssueBlockAttribute] === 'string'
      ? // There's a type mismatch here because CreateIssueBlockProps requires `children` but we are supposed to pass that as the third argument
        createElement(CreateIssueBlock, {} as {children: string}, props[createIssueBlockAttribute])
      : fallthrough,
}

export default function createIssueExtension(): CopilotMarkdownExtension {
  return {
    transformMarkdown: tree =>
      visit(tree, 'code', node => {
        if (node.lang !== 'yaml') return

        const type = stripQuotes(typeRawRegex.exec(node.meta ?? '')?.groups?.type ?? '')
        if (type !== 'issue') return

        node.data = {
          hName: 'div',
          hProperties: {
            // With the new renderer, things are easier if we just use attributes instead of trying to work with contents
            [createIssueBlockProperty]: node.value,
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
          i !== undefined &&
          node.tagName === 'pre' &&
          node.children?.length === 1 &&
          child?.type === 'element' &&
          createIssueBlockProperty in child.properties
        )
          parent.children.splice(i, 1, child)
      }),
    reactComponents,
  }
}

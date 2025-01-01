import type {Root} from 'mdast'
import {escapeHTMLAttribute, getStaticAssetsURL, type Delimiter} from '../utils'
import type {InlineMathNode} from './mdast'
import {findAndReplace} from 'mdast-util-find-and-replace'

function buildInlineNode(math: string): InlineMathNode {
  return {
    type: 'inlinemath',
    value: math,
    data: {
      hName: 'math-renderer',
      hProperties: {
        className: 'js-inline-math',
        style: 'display: inline-block;',
        dataStaticUrl: escapeHTMLAttribute(getStaticAssetsURL()),
      },
      hChildren: [{type: 'text', value: math}],
    },
  }
}

export const inlinemath = (delimiters: readonly Delimiter[]) => {
  const expressions = delimiters.map(
    // eslint-disable-next-line escompat/no-regexp-lookbehind
    ({open, close}) => new RegExp(`(?<![a-z0-9])${open.source}(.+?)${close.source}(?![a-z0-9])`, 'g'),
  )

  return (tree: Root) =>
    findAndReplace(
      tree,
      expressions.map(regex => [regex, (_, math: string) => buildInlineNode(math)]),
    )
}

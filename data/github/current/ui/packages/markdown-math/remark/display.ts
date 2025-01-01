import {escapeHTMLAttribute, getStaticAssetsURL, type Delimiter} from '../utils'
import type {Code, Root} from 'mdast'

import {findAndReplace} from 'mdast-util-find-and-replace'
import type {DisplayMathNode} from './mdast'
import {visit} from 'unist-util-visit'

function buildDisplayNode(math: string): DisplayMathNode {
  return {
    type: 'displaymath',
    value: math,
    data: {
      hName: 'math-renderer',
      hProperties: {
        className: 'js-display-math',
        style: 'display: block; text-align: center;',
        dataStaticUrl: escapeHTMLAttribute(getStaticAssetsURL()),
      },
      hChildren: [{type: 'text', value: math}],
    },
  }
}

export const displaymath = (delimiters: readonly Delimiter[]) => {
  const expressions = delimiters.map(
    ({open, close}) => new RegExp(`(?:^|\\n) *${open.source}((?:\n|.)+?)${close.source}(?= *(?:\\n|$))`, 'g'),
  )

  return (tree: Root) =>
    findAndReplace(
      tree,
      expressions.map(regex => [regex, (_, math: string) => buildDisplayNode(math)]),
    )
}

export const codemath = (languages: ReadonlySet<string>) => (tree: Root) =>
  visit(tree, 'code', (node: Code, i, parent) => {
    if (!node.lang || !languages.has(node.lang) || !parent || i === undefined) return

    parent.children.splice(i, 1, buildDisplayNode(node.value))
  })

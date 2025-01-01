import {
  getHiddenUnicodeReplacement,
  hasHiddenUnicodeCharacters,
  hiddenUnicodeCharacterHTMLString,
  splitAroundHiddenUnicodeCharacters,
} from '@github-ui/hidden-unicode-banner/utils'
import {parseDirectives} from '../ast-utils/parse-node'
import type {HighlightingStrategy, StylingDirective, StylingDirectivesLine} from '../types'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {showHiddenUnicodeCharactersHTML} from '@github-ui/hidden-unicode-banner/HiddenUnicodeCharacter'

interface SyntaxTree extends StylingDirective {
  nodes: Array<SyntaxTree | TokenNode>
}

interface TokenNode extends StylingDirective {
  text: string
}

type Offset = {value: number}

// Exported for testing
export function buildCodeHTML(
  rawText: string | undefined,
  directives: StylingDirectivesLine | undefined,
  strategy: HighlightingStrategy,
  tabSize: number,
  exposeHiddenUnicodeCharacters: boolean,
): SafeHTMLString {
  rawText ||= '\n'

  // gracefully handle both the old and new directive formats
  const normalizedDirectives = parseDirectives(directives ?? [])
  const tree = makeSyntaxTree(rawText, normalizedDirectives, strategy, tabSize)
  const out: string[] = []
  appendHTMLNodesForSubtree(tree, strategy, exposeHiddenUnicodeCharacters, out)
  return out.join('') as SafeHTMLString
}

function appendHTMLNodesForSubtree(
  node: SyntaxTree,
  strategy: HighlightingStrategy,
  exposeHiddenUnicodeCharacters: boolean,
  out: string[],
) {
  if (node.c) {
    // eslint-disable-next-line github/unescaped-html-literal
    out.push(`<span class="${escapeHTML(node.c)}">`)
  }

  for (const child of node.nodes) {
    if (isTree(child)) {
      appendHTMLNodesForSubtree(child, strategy, exposeHiddenUnicodeCharacters, out)
    } else {
      out.push(makeHTMLToken(child, strategy, exposeHiddenUnicodeCharacters))
    }
  }

  if (node.c) {
    out.push(`</span>`)
  }
}

function makeHTMLToken(
  node: TokenNode,
  strategy: HighlightingStrategy,
  exposeHiddenUnicodeCharacters: boolean,
): string {
  switch (strategy) {
    case 'data-attribute': {
      const text = escapeHTML(node.text)

      if (exposeHiddenUnicodeCharacters && hasHiddenUnicodeCharacters(text)) {
        const splitText = splitAroundHiddenUnicodeCharacters(text)
        const children = splitText.map(segment => {
          const hiddenUnicodeReplacement = getHiddenUnicodeReplacement(segment)
          return hiddenUnicodeReplacement
            ? hiddenUnicodeCharacterHTMLString(hiddenUnicodeReplacement)
            : makeHTMLToken({...node, text: segment, c: ''}, strategy, false)
        })
        // eslint-disable-next-line github/unescaped-html-literal
        return node.c ? `<span class="${escapeHTML(node.c)}">${children.join('')}</span>` : children.join('')
      }

      return node.c
        ? // eslint-disable-next-line github/unescaped-html-literal
          `<span class="${escapeHTML(node.c)}" data-code-text="${text}"></span>`
        : // eslint-disable-next-line github/unescaped-html-literal
          `<span data-code-text="${text}"></span>`
    }
    case 'separated-characters-chunked':
    case 'separated-characters': {
      if (node.text && !node.text.trim()) {
        // don't split empty strings / tabs, small optimization to cut down on the number of elements
        return makeHTMLToken({...node}, 'data-attribute', exposeHiddenUnicodeCharacters)
      }

      let nodeText = [...node.text]

      if (strategy === 'separated-characters-chunked' && !exposeHiddenUnicodeCharacters) {
        // chunk characters together in groups of 2
        nodeText = node.text.match(/.{1,2}/g) ?? nodeText
      }

      const separatedText = [...nodeText]
        .map(char => {
          const hiddenUnicodeReplacement = exposeHiddenUnicodeCharacters ? getHiddenUnicodeReplacement(char) : undefined
          return hiddenUnicodeReplacement
            ? hiddenUnicodeCharacterHTMLString(hiddenUnicodeReplacement)
            : // eslint-disable-next-line github/unescaped-html-literal
              `<span data-code-text="${escapeHTML(char)}"></span>`
        })
        .join('')
      // eslint-disable-next-line github/unescaped-html-literal
      return node.c ? `<span class="${escapeHTML(node.c)}">${separatedText}</span>` : separatedText
    }
    case 'css-highlighting':
    case 'plain':
    default: {
      const text = escapeHTML(node.text)
      const contents = exposeHiddenUnicodeCharacters ? showHiddenUnicodeCharactersHTML(text) ?? text : text
      // eslint-disable-next-line github/unescaped-html-literal
      return node.c ? `<span class="${escapeHTML(node.c)}">${contents}</span>` : contents
    }
  }
}

function makeSyntaxTree(
  rawText: string,
  stylingDirectivesLine: StylingDirective[] | undefined,
  strategy: HighlightingStrategy,
  tabSize: number,
): SyntaxTree {
  const offset: Offset = {value: 0}
  const tree: SyntaxTree = {nodes: [], s: 0, e: rawText.length, c: ''}

  // Consider only non-empty directives
  const directives = stylingDirectivesLine?.filter(dir => dir.e > dir.s)

  if (!directives || directives.length === 0) {
    tree.nodes.push(makeNode('', rawText, 0, rawText.length, offset, tabSize, strategy))
    return tree
  }

  const currentParentStack = [tree]
  for (let i = 0; i < directives.length; i++) {
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    const current = directives[i]!
    const next = directives[i + 1]
    let parent = currentParentStack[currentParentStack.length - 1] ?? tree
    const previous = parent.nodes[parent.nodes.length - 1]

    if (parent.nodes.length === 0 && current.s > parent.s) {
      // Fill the space between the beginning of the parent and the first child (current)
      const beginningOfParent = makeNode('', rawText, parent.s, current.s, offset, tabSize, strategy)
      parent.nodes.push(beginningOfParent)
    } else if (previous && current.s > previous.e) {
      // Fill the space between the end of the previous node and the current one
      const inBetween = makeNode('', rawText, previous.e, current.s, offset, tabSize, strategy)
      parent.nodes.push(inBetween)
    }

    const isContainer = next && next.s < current.e
    if (isContainer) {
      // The current directive contains sub-directives. Make it the new parent, and recurse.
      const newContainer = {...current, nodes: []}
      parent.nodes.push(newContainer)
      currentParentStack.push(newContainer)
    } else {
      // Create a node for the current directive
      const newNode = makeNode(current.c, rawText, current.s, current.e, offset, tabSize, strategy)
      parent.nodes.push(newNode)
    }

    if (next && next.s >= parent.e) {
      let previousParentEnd = current.e
      if (parent.e > previousParentEnd) {
        // Fill the space between the end of the current directive and the end of the parent node
        const restOfCurrentParent = makeNode('', rawText, previousParentEnd, parent.e, offset, tabSize, strategy)
        parent.nodes.push(restOfCurrentParent)
        previousParentEnd = parent.e
      }

      // We are done with the nodes in the current parent. Go back to the grandparent.
      while (currentParentStack.length > 1 && next.s >= parent.e) {
        //pop off all current parents, filling in data as necessary due to nested parents
        currentParentStack.pop()
        parent = currentParentStack[currentParentStack.length - 1] ?? tree
        if (currentParentStack.length > 1 && next.s >= parent.e && parent.e > previousParentEnd) {
          // Fill the space between the end of the current directive and the end of the parent node, but only if
          // the parent is not the same scope as the previous parent
          const restOfCurrentParent = makeNode('', rawText, previousParentEnd, parent.e, offset, tabSize, strategy)
          previousParentEnd = parent.e
          parent.nodes.push(restOfCurrentParent)
        }
      }
    }
  }

  // Fill in the remaining space in any parents left in the stack
  while (currentParentStack.length > 0) {
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    const parent = currentParentStack.pop()!

    const lastNode = parent.nodes[parent.nodes.length - 1]
    if (lastNode && lastNode.e < parent.e) {
      // Fill the space between the end of the last directive and the end of the parent.
      const restOfParent = makeNode('', rawText, lastNode.e, parent.e, offset, tabSize, strategy)
      parent.nodes.push(restOfParent)
    }
  }

  return tree
}

function makeNode(
  cssClass: string,
  rawText: string,
  start: number,
  end: number,
  offset: Offset,
  tabSize: number,
  strategy: HighlightingStrategy,
): TokenNode {
  const substring = rawText.substring(start, end)
  const text = strategy !== 'plain' ? convertTabsToSpaces(substring, tabSize, offset) : substring
  return {c: cssClass, s: start, e: end, text}
}

function isTree(node: SyntaxTree | TokenNode): node is SyntaxTree {
  return 'nodes' in node
}

/**
 * Converts a string containing tabs to a string where all tabs have been
 * replaced with the appropriate number of spaces.
 *
 * @param text The string to convert
 * @param tabSize The number of character widths between tab stops
 * @param offset The position on a line at which the string begins
 *
 * @remarks
 * This is necessary because our html format with no text nodes uses css to
 * put the code text on the page. Unfortunately, the browser does not interpret
 * the css-inserted text of adjacent nodes as being part of the same contiguous
 * block of text. That means that each node is treated as if it were at the
 * start of a line, so tabs do not necessarily get the correct width.
 * Converting them to the right number of spaces here fixes the problem. This
 * does not affect copying/pasting code correctly because the
 * syntax-highlighted overlay is not selectable.
 */
function convertTabsToSpaces(text: string, tabSize: number, offset: Offset) {
  const out: string[] = []
  for (const char of text) {
    if (char === '\t') {
      const numSpaces = tabSize - (offset.value % tabSize)
      out.push(spaces(numSpaces))
      offset.value += numSpaces
    } else {
      out.push(char)
      // Browser textareas appear to count the number of code points rather
      // than the display width of each character when determining tab stops.
      offset.value += numberOfCodePoints(char)
    }
  }
  return out.join('')
}

function spaces(count: number): string {
  return new Array(count).fill(' ').join('')
}

function numberOfCodePoints(str: string): number {
  return Array.from(str).length
}

/**
 * 1. No, there is no standard library solution for this
 * 2. Yes, this is actually the fastest way; the switch statement is slightly
 *    faster than a object lookup or map, and in aggregate, that adds up.
 */
function escapeHTML(unsafe: string): SafeHTMLString {
  return unsafe.replace(/[&<>"']/g, escapeHTMLChar) as SafeHTMLString
}

function escapeHTMLChar(char: string): string {
  switch (char) {
    case '&':
      return '&amp;'
    case '<':
      return '&lt;'
    case '>':
      return '&gt;'
    case '"':
      return '&quot;'
    case "'":
      return '&#039;'
    default:
      return char
  }
}

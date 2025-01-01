import type {MarkedExtension} from 'marked'

import {codemath, displaymath} from './display'
import {inlinemath} from './inline'
import {
  defaultCodeBlockLanguages,
  defaultDisplayDelimiters,
  defaultInlineDelimiters,
  type MarkdownMathOptions,
} from '../options'

/**
 * Marked.js extension for rendering LaTeX mathematics. Supports display / block math, inline math, and code block
 * math.
 *
 * Usage:
 *
 * ```
 * new Marked({gfm: true, breaks: true}, markedMath())
 */
export const markedMath = ({
  displayDelimiters = defaultDisplayDelimiters,
  inlineDelimiters = defaultInlineDelimiters,
  codeBlockLanguages = defaultCodeBlockLanguages,
}: MarkdownMathOptions = {}): MarkedExtension => ({
  extensions: [displaymath(displayDelimiters), inlinemath(inlineDelimiters)],
  renderer: {
    code: codemath(codeBlockLanguages),
  },
})

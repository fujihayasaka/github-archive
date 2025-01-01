import type {Root} from 'mdast'
import {
  defaultCodeBlockLanguages,
  defaultDisplayDelimiters,
  defaultInlineDelimiters,
  type MarkdownMathOptions,
} from '../options'
import {codemath, displaymath} from './display'
import {inlinemath} from './inline'

/**
 * Remark extension for rendering LaTeX mathematics. Supports display / block math, inline math, and code block
 * math. Applies config to prepare for transformation to HTML using `mdast-util-to-hast`.
 */
export const remarkMath =
  ({
    displayDelimiters = defaultDisplayDelimiters,
    inlineDelimiters = defaultInlineDelimiters,
    codeBlockLanguages = defaultCodeBlockLanguages,
  }: MarkdownMathOptions = {}) =>
  (tree: Root) => {
    displaymath(displayDelimiters)(tree)
    codemath(codeBlockLanguages)(tree)
    inlinemath(inlineDelimiters)(tree)
  }

import type {MarkedExtension} from 'marked'
import type {Delimiter} from './utils'
import {codemath, displaymath} from './display'
import {inlinemath} from './inline'

export const defaultDisplayDelimiters = [{open: /\$\$/, close: /\$\$/}] as const

/**
 * By default we support:
 * 1. Single dollar signs without inside whitespace: `$x$` but not `$ x $`
 * 2. Double dollar signs without inside whitespace: `$$x$$` but not `$$ x $$`. NOTE this is an exception to (1) since
 *    we technically have single dollar signs without leading whitespace here!
 * 3. Dollar-backticks with or without inside whitespace: ``$`x`$``
 */
export const defaultInlineDelimiters = [
  // Order is important! We want to ensure we 'eat' the entire delimiter, so we put the longest delimiters first
  // Otherwise the $` would be treated as $ with a backtick inside
  {open: /\$`/, close: /`\$/},
  // Double dollar sign delimiters are also supported on github.com (though not documented)
  {open: /\$\$(?! )/, close: /(?<! )\$\$/},
  // Single dollar sign delimiters may not have a space or dollar sign immediately inside
  {open: /\$(?![ $])/, close: /(?<![ $])\$/},
] as const

export const defaultCodeBlockLanguages: ReadonlySet<string> = new Set(['math'])

export interface MarkedMathOptions {
  /**
   * Delimiter regular expressions for display (block) math. Set to empty array to disable display math.
   * @default defaultDisplayDelimiters
   */
  displayDelimiters?: readonly Delimiter[]
  /**
   * Delimiter regular expressions for inline math. Set to empty array to disable inline math.
   * @default defaultInlineDelimiters
   */
  inlineDelimiters?: readonly Delimiter[]
  /**
   * Language names for codeblocks to render as math. Set to empty set to disable code block math.
   * @default defaultCodeBlockLanguages
   */
  codeBlockLanguages?: ReadonlySet<string>
}

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
}: MarkedMathOptions = {}): MarkedExtension => ({
  extensions: [displaymath(displayDelimiters), inlinemath(inlineDelimiters)],
  renderer: {
    code: codemath(codeBlockLanguages),
  },
})

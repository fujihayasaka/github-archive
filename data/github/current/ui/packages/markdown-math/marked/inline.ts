import {
  escapeHTMLAttribute,
  escapeLatexForHTML,
  getStaticAssetsURL,
  latexRenderer,
  regexStart,
  regexTokenizer,
  type Delimiter,
} from '../utils'
import type {TokenizerAndRendererExtension} from 'marked'

const buildInlineHTML = (latex: string) =>
  // eslint-disable-next-line github/unescaped-html-literal
  `<math-renderer class="js-inline-math" style="display: inline-block" data-static-url="${escapeHTMLAttribute(
    getStaticAssetsURL(),
  )}">${escapeLatexForHTML(latex)}</math-renderer>`

/** Marked tokenizer and renderer extension for inline math. */
export function inlinemath(delimiters: readonly Delimiter[]): TokenizerAndRendererExtension {
  const start = new RegExp(`${delimiters.map(d => d.open.source).join('|')}`)
  /**
   * We need a separate regex for each delimiter so we can ensure the end matches the start delimiter.
   *
   * Explanation:
   *   - `^`: Anchor to start of current chunk of source as required (https://marked.js.org/using_pro#extensions)
   *   - open delimiter
   *   - `(?<latex>.+?)`: In a named group called "latex":
   *     - `.+?`: At least one of anything except newlines. Lazy so we stop at the first instance of a close delimiter
   *   - close delimiter
   *   - `(?:\s|$)`: a whitespace or end of string
   */
  const rules = delimiters.map(({open, close}) => new RegExp(`^${open.source}(?<latex>.+?)${close.source}`))
  const name = 'inlinemath'

  return {
    name,
    level: 'inline',
    start: regexStart(start),
    tokenizer: regexTokenizer(name, rules),
    renderer: latexRenderer(buildInlineHTML),
  }
}

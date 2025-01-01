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

export const buildDisplayHTML = (latex: string) =>
  // eslint-disable-next-line github/unescaped-html-literal
  `<math-renderer class="js-display-math" style="display: block; text-align: center;" data-static-url="${escapeHTMLAttribute(
    getStaticAssetsURL(),
  )}">${escapeLatexForHTML(latex)}</math-renderer>
`

/** Marked tokenizer and renderer extension for display (block) math. */
export function displaymath(delimiters: readonly Delimiter[]): TokenizerAndRendererExtension {
  /**
   * Matches the "next potential start of the custom token". We're looking for a newline followed by any amount of
   * whitespace followed by an open delimiter.
   */
  const start = new RegExp(`\\n\\s*(?:${delimiters.map(d => d.open.source).join('|')})`)
  /**
   * We need a separate regex for each delimiter so we can ensure the end matches the start delimiter.
   *
   * Explanation:
   *   - `^`: Anchor to start of current chunk of source as required (https://marked.js.org/using_pro#extensions)
   *   - open delimiter
   *   - `(?<latex>...)`: In a named group called "latex":
   *     - `(?:\n|.)+?`: At least one of *anything* including newlines. Lazy so we stop at the first instance of a
   *       close delimiter
   *   - close delimiter
   *   - `(?= *(?:\n|$))`: Lookahead for any amount of spaces then either a newline or the end of the text (prevents
   *     non-whitespace from immediately following the close delimiter)
   */
  const rules = delimiters.map(
    ({open, close}) => new RegExp(`^${open.source}(?<latex>(?:\n|.)+?)${close.source}(?= *(?:\\n|$))`),
  )
  const name = 'displaymath'

  return {
    name,
    level: 'block',
    start: regexStart(start),
    tokenizer: regexTokenizer(name, rules),
    renderer: latexRenderer(buildDisplayHTML),
  }
}

export const codemath = (languages: ReadonlySet<string>) => (text: string, lang?: string) =>
  lang && languages.has(lang) ? buildDisplayHTML(text) : false

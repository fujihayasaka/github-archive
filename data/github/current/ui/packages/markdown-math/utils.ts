import type {Tokens} from 'marked'

export interface Delimiter {
  readonly open: RegExp
  readonly close: RegExp
}

export const regexStart = (regex: RegExp) => (src: string) => src.match(regex)?.index

/** Tokenize based on a set of regular expressions. Returns the first match, spreading named capture groups into the token. */
export const regexTokenizer =
  (name: string, rules: RegExp[]) =>
  (src: string): Tokens.Generic | undefined => {
    for (const rule of rules) {
      const match = src.match(rule)
      if (match)
        return {
          type: name,
          raw: match[0],
          ...match.groups,
        }
    }
  }

export const latexRenderer = (buildHtml: (latex: string) => string) => (token: Tokens.Generic) => {
  if (typeof token.latex !== 'string') throw new Error('Unrecognized token passed to math renderer')
  return buildHtml(token.latex)
}

let staticAssetsURL = null // cache to avoid unecessary DOM queries

export const getStaticAssetsURL = () =>
  (staticAssetsURL ??= document.querySelector<HTMLLinkElement>('link[rel="assets"]')?.href ?? '')

/**
 * `<` signs are valid math characters, so we need to escape them to avoid being interpreted as HTML. If we only
 * with `&lt;`, they will be escaped in the initial HTML but get reinterpreted as HTML by either the MathJax parser or
 * in the MathML output (not 100% where this happens). So we need to double-escape since this is going through two HTML
 * rendering steps.
 */
export const escapeLatexForHTML = (latex: string) => latex.replaceAll('<', '&amp;lt;')

/** Escapes double quotes for attributes. */
export const escapeHTMLAttribute = (value: string) => value.replaceAll('"', '&quot;')

import type {Tokens} from 'marked'

/** Matches code block languages and types in the form `list type=issue`. */
const langTypeRegex = /^(?<lang>[^\s]+)\s+type=(?<type>[^\s]+)/

/**
 * Matches code block language abd type in the form of:
 *
 *  ```list
 *  type=issue
 *
 */
const langTypeRawRegex = /^(?:`{3,}|~{3,})+(?<lang>[^\s]+)\ntype=(?<type>[^\s]+)/

/** Matches the type in the first line of a code block. */
export const typeRawRegex = /^type=(?<type>[^\s]+)\n?/

/** Strips surrounding single or double quotes. */
export const stripQuotes = (str: string) =>
  (str.startsWith('"') && str.endsWith('"')) || (str.startsWith("'") && str.endsWith("'")) ? str.slice(1, -1) : str

export function isCodeToken(token: Tokens.Generic): token is Tokens.Code {
  return token.type === 'code'
}

export function getLangAndType(token: Tokens.Code): {lang: string | undefined; type: string | undefined} {
  let match = token.lang && langTypeRegex.exec(token.lang)

  if (!match) {
    // Maybe it's the multi-line form
    match = langTypeRawRegex.exec(token.raw)
    if (match) {
      token.text = token.text.replace(typeRawRegex, '')
    }
  }

  if (match?.groups) {
    const {lang, type} = match.groups
    const typeWithoutQuotes = type && stripQuotes(type)
    return {lang, type: typeWithoutQuotes}
  }
  return {lang: undefined, type: undefined}
}

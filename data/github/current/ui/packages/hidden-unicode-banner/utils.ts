import type {SafeHTMLString} from '@github-ui/safe-html'

// There are 9 unicode codepoints in two contiguous blocks that act as
// bidi (bidirectional) control characters and 2 other codepoints that
// produce unrenderable text which can obscure malicious code:
// +-----------+----------------------------------+
// | codepoint | Control character name           |
// +-----------+----------------------------------+
// |  \u202A   | LEFT-TO-RIGHT EMBEDDING (LRE)    |
// |  \u202B   | RIGHT-TO-LEFT EMBEDDING (RLE)    |
// |  \u202C   | POP DIRECTIONAL FORMATTING (PDF) |
// |  \u202D   | LEFT-TO-RIGHT OVERRIDE (LRO)     |
// |  \u202E   | RIGHT-TO-LEFT OVERRIDE (RLO)     |
// |        [ ... ].                              |
// |  \u2066   | LEFT-TO-RIGHT ISOLATE (LRI)      |
// |  \u2067   | RIGHT-TO-LEFT ISOLATE (RLI)      |
// |  \u2068   | FIRST STRONG ISOLATE (FSI)       |
// |  \u2069   | POP DIRECTIONAL ISOLATE (PDI)    |
// |  \uE0001  | LANGUAGE TAG (TAG)               |
// |  \uE007F  | CANCEL TAG (TAG)                 |
// +-----------+----------------------------------+
const hiddenUnicodeRegex = /[\u202A-\u202E]|[\u2066-\u2069]|\u{E0001}|\u{E007F}/u
const hiddenUnicodeRegexG = /[\u202A-\u202E]|[\u2066-\u2069]|\u{E0001}|\u{E007F}/gu
const hiddenUnicodeBoundaryRegex = /([\u202A-\u202E]|[\u2066-\u2069]|\u{E0001}|\u{E007F})/gu
const hiddenUnicodeReplacements = {
  '\u202A': 'U+202A', // LEFT-TO-RIGHT EMBEDDING
  '\u202B': 'U+202B', // RIGHT-TO-LEFT EMBEDDING
  '\u202C': 'U+202C', // POP DIRECTIONAL FORMATTING
  '\u202D': 'U+202D', // LEFT-TO-RIGHT OVERRIDE
  '\u202E': 'U+202E', // RIGHT-TO-LEFT OVERRIDE
  '\u2066': 'U+2066', // LEFT-TO-RIGHT ISOLATE
  '\u2067': 'U+2067', // RIGHT-TO-LEFT ISOLATE
  '\u2068': 'U+2068', // FIRST STRONG ISOLATE
  '\u2069': 'U+2069', // POP DIRECTIONAL ISOLATE
  '\u{E0001}': 'U+E0001', // LANGUAGE TAG
  '\u{E007F}': 'U+E007F', // CANCEL TAG
} as const
type HiddenUnicodeChar = keyof typeof hiddenUnicodeReplacements
export type HiddenUnicodeReplacement = (typeof hiddenUnicodeReplacements)[HiddenUnicodeChar]
export const hiddenUnicodeReplacementMap = new Map<string, HiddenUnicodeReplacement>(
  Object.entries(hiddenUnicodeReplacements),
)

export function hiddenUnicodeCharacterHTMLString(
  hiddenUnicodeReplacementString: HiddenUnicodeReplacement,
): SafeHTMLString {
  // We purposely don't want to escape the HTML because we know that the string will be from the replacementMap
  // eslint-disable-next-line github/unescaped-html-literal
  return `<span class="hidden-unicode-replacement" data-code-text="${hiddenUnicodeReplacementString}"></span>` as SafeHTMLString
  // Casting to SafeHTMLString is safe because we know this exact html,
  // and we know that `hiddenUnicodeReplacementString` can only have a few specific values
}

/**
 * Split the given text into an array of strings and hidden Unicode control characters.
 */
export function splitAroundHiddenUnicodeCharacters(text: SafeHTMLString): SafeHTMLString[] {
  return text.split(hiddenUnicodeBoundaryRegex) as SafeHTMLString[]
}

export function showHiddenUnicodeCharactersRaw(text: string): string {
  if (!hasHiddenUnicodeCharacters(text)) return text

  return text.replaceAll(hiddenUnicodeRegexG, (char: string) => hiddenUnicodeReplacementMap.get(char) ?? '')
}

export function hasHiddenUnicodeCharacters(text: string): boolean {
  return hiddenUnicodeRegex.test(text)
}

export function getHiddenUnicodeReplacement(char: string): HiddenUnicodeReplacement | undefined {
  return hiddenUnicodeReplacementMap.get(char)
}

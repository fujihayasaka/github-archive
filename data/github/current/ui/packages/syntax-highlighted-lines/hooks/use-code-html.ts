import {useMemo} from 'react'
import type {HighlightingStrategy, StylingDirectivesLine} from '../types'
import {buildCodeHTML} from '../utils/build-code-html'
import type {SafeHTMLString} from '@github-ui/safe-html'

/**
 * Given the possible sources of syntax highlighting from the server, returns the appropriate syntax-highlighted HTML
 */
export function useCodeHTML(
  lineHtml: SafeHTMLString | undefined,
  directives: StylingDirectivesLine | undefined,
  rawText: string | undefined,
  strategy: HighlightingStrategy = 'plain',
  tabSize: number,
  hiddenUnicodeShown: boolean,
): SafeHTMLString {
  return useMemo(
    () => lineHtml ?? buildCodeHTML(rawText, directives, strategy, tabSize, hiddenUnicodeShown),
    [rawText, lineHtml, directives, strategy, tabSize, hiddenUnicodeShown],
  )
}

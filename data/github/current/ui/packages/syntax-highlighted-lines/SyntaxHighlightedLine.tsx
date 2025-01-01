import {useRef} from 'react'
import {useHighlight} from './hooks/use-highlight'
import type {StylingDirectivesLine} from './types'
import './SyntaxHighlightedLines.module.css'

export type SyntaxHighlightedLineProps = {
  html: string
  styleDirectives: StylingDirectivesLine | undefined
}

/**
 * Applies client-side syntax highlighting to a single line of code using the provided style directives.
 * The highlighting is applied via the CSS Custom Highlighting API.
 * @param {string} html
 * @param {StylingDirectivesLine} styleDirectives
 * @returns {JSX.Element}
 */
export function SyntaxHighlightedLine({html, styleDirectives}: SyntaxHighlightedLineProps) {
  const ref = useRef<HTMLDivElement>(null)

  useHighlight(ref, styleDirectives)

  return <div ref={ref}>{html}</div>
}

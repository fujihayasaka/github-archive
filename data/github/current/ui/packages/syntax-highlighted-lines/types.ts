export type StylingDirectivesDocument = StylingDirectivesLine[]

export type StylingDirectivesLine = StylingDirective[]

/*
  s = start of the directive
  e = endo f the directive
  c = cssClass for the directive
*/
export interface StylingDirective {
  s: number
  e: number
  c: string
}

/**
 * A directive node is an array of 3 elements:
 * 1. The start of the directive
 * 2. The end of the directive
 * 3. The css class for the directive
 */
export type StylingDirectiveNode = [number, number, string]

export type HighlightingStrategy = 'none' | 'treelights' | 'client-side'

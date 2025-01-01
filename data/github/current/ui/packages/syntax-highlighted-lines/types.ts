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

export type HighlightingStrategy = 'none' | 'treelights' | 'client-side'

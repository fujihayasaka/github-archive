export type StylingDirectivesDocument = StylingDirectivesLine[]

export type StylingDirectivesLine = StylingDirective[] | StylingDirectiveNode[]

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

/**
 * None - No syntax highlighting
 * Server-side - Syntax highlighting is done on the server and injected into the HTML
 * Client-side - Syntax highlighting is done on the client using the ClientSyntaxHighlightingStrategy
 */
export type HighlightingSource = 'none' | 'server-side' | 'client-side'

/**
 * Client-side syntax highlighting strategies.
 * These strategies determine how the syntax highlighting is applied on the client side.
 * - 'plain' - No syntax highlighting, just plain text.
 * - 'data-attribute' - Uses data attributes to apply syntax highlighting. Default for Code View.
 * - 'separated-characters' - Highlights each character separately via data-attributes. Legacy Firefox support.
 * - 'separated-characters-chunked' - Highlights characters in chunks. Same as 'separated-characters' but with chunking for performance.
 * - 'css-highlighting' - Uses CSS Custom Highlighting API to apply syntax highlighting. Early implementation, not widely supported.
 */
export type HighlightingStrategy =
  | 'plain'
  | 'data-attribute'
  | 'separated-characters' // deprecated in favor of 'separated-characters-chunked'
  | 'separated-characters-chunked'
  | 'css-highlighting'
